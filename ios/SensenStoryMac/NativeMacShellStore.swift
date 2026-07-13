import Combine
import Foundation

@MainActor
final class NativeMacShellStore: ObservableObject {
    @Published private(set) var snapshot = DashboardSnapshot(
        sessionCount: 0,
        messageCount: 0,
        memoryCount: 0,
        journalCount: 0
    )
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var memories: [MemoryEntry] = []
    @Published private(set) var journals: [JournalEntry] = []
    @Published private(set) var stateProfiles: [StateProfile] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var selectedSessionID: String?
    @Published private(set) var latestAssessment: UserConversationAssessment?
    @Published private(set) var closeSummary: SessionCloseSummary?
    @Published private(set) var databasePath = "尚未打开本地数据库"
    @Published private(set) var databaseError: String?
    @Published private(set) var backendStatus: BackendConnectionStatus
    @Published private(set) var isCheckingBackend = false
    @Published private(set) var isSending = false
    @Published private(set) var operationStatus: String?
    @Published var notice: String?
    @Published var apiKeyText: String

    private let deepSeekService: LocalDeepSeekService
    private let secureSettings: SecureSettingsStore
    private let database: SQLiteDatabase?
    private var sendTask: Task<Void, Never>?
    private var hasBootstrapped = false
    private let maxDisplayMessages = 120

    init(
        deepSeekService: LocalDeepSeekService = LocalDeepSeekService(),
        secureSettings: SecureSettingsStore = .shared,
        database: SQLiteDatabase? = nil
    ) {
        self.deepSeekService = deepSeekService
        self.secureSettings = secureSettings
        self.database = database ?? (try? SQLiteDatabase())
        let savedAPIKey = secureSettings.deepSeekAPIKey() ?? ""
        apiKeyText = savedAPIKey
        backendStatus = BackendConnectionStatus(
            state: savedAPIKey.isEmpty ? .unknown : .online,
            baseURL: "api.deepseek.com",
            detail: savedAPIKey.isEmpty
                ? "尚未配置 DeepSeek API Key。"
                : "DeepSeek Key 已配置；原生 App 将直接调用模型。",
            lastCheckedAt: nil
        )
        loadLocalCache()
    }

    deinit {
        sendTask?.cancel()
    }

    var selectedCharacter: CompanionCharacter {
        let latestCharacterID = messages.last(where: { $0.role == .assistant })?.characterID
        return CompanionFixtures.character(id: latestCharacterID) ?? CompanionFixtures.characters[0]
    }

    var isDeepSeekConfigured: Bool {
        !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        loadLocalCache()
    }

    func loadLocalCache() {
        guard let database else {
            databaseError = "无法打开原生 App 的 SQLite 数据库。"
            return
        }
        databasePath = database.path
        snapshot = DashboardSnapshot(
            sessionCount: database.count(table: "sessions"),
            messageCount: database.count(table: "messages"),
            memoryCount: database.count(table: "memories"),
            journalCount: database.count(table: "journals")
        )
        sessions = database.sessions(limit: 100)
        memories = database.memories(limit: 200)
        journals = database.journals(limit: 120)
        stateProfiles = database.stateProfiles(limit: 40)
        if let selectedSessionID {
            messages = bounded(database.messages(sessionID: selectedSessionID, limit: maxDisplayMessages))
        }
        databaseError = nil
    }

    func newConversation() {
        cancelSend()
        deepSeekService.resetSession()
        selectedSessionID = nil
        messages = []
        latestAssessment = nil
        closeSummary = nil
        notice = nil
        operationStatus = nil
    }

    func openSession(_ sessionID: String) {
        cancelSend()
        selectedSessionID = sessionID
        deepSeekService.useSession(sessionID)
        messages = bounded(database?.messages(sessionID: sessionID, limit: maxDisplayMessages) ?? [])
        latestAssessment = nil
        closeSummary = nil
        notice = nil
    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard let database else {
            notice = "本地数据库不可用，暂时无法发送。"
            return
        }
        let apiKey = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            notice = "请先在设置中填写 DeepSeek API Key。"
            return
        }

        let pendingUserID = "pending-user-\(UUID().uuidString)"
        appendMessage(
            ChatMessage(
                id: pendingUserID,
                role: .user,
                content: text,
                characterID: nil,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        )
        latestAssessment = nil
        closeSummary = nil
        notice = nil
        isSending = true
        operationStatus = "正在并行生成快速回应和理解计划…"

        let correlationID = SendInstrumentation.shared.beginSend(
            messageLength: text.utf8.count,
            isGroupMode: false
        )
        SendInstrumentation.shared.recordPhase(.sendTaskStarted, correlationID: correlationID)
        let character = selectedCharacter

        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                SendInstrumentation.shared.recordPhase(.requestEncodeStarted, correlationID: correlationID)
                let result = try await deepSeekService.send(
                    text: text,
                    character: character,
                    apiKey: apiKey,
                    database: database
                ) { [weak self] quickMessage in
                    guard let self else { return }
                    SendInstrumentation.shared.recordPhase(.firstResponseReceived, correlationID: correlationID)
                    self.appendMessage(quickMessage)
                    self.operationStatus = "快速回应已到达，后台仍在判断是否需要深入回应…"
                }

                guard !Task.isCancelled else {
                    finishSend(correlationID: correlationID, success: false, error: "cancelled")
                    return
                }

                selectedSessionID = result.sessionID
                latestAssessment = result.assessment
                messages = bounded(database.messages(sessionID: result.sessionID, limit: maxDisplayMessages))
                loadLocalCache()
                notice = noticeForNextAction(result.nextAction, hasFollowUp: result.followUpReply != nil)
                backendStatus = BackendConnectionStatus(
                    state: .online,
                    baseURL: "api.deepseek.com",
                    detail: "本轮由原生 App 直接调用 DeepSeek 完成。",
                    lastCheckedAt: Date()
                )
                finishSend(correlationID: correlationID, success: true, error: nil)
            } catch {
                if let sessionID = deepSeekService.currentSessionID {
                    selectedSessionID = sessionID
                    messages = bounded(database.messages(sessionID: sessionID, limit: maxDisplayMessages))
                    loadLocalCache()
                }
                notice = "DeepSeek 请求失败：\(error.localizedDescription)"
                backendStatus = BackendConnectionStatus(
                    state: .fallback,
                    baseURL: "api.deepseek.com",
                    detail: error.localizedDescription,
                    lastCheckedAt: Date()
                )
                finishSend(correlationID: correlationID, success: false, error: error.localizedDescription)
            }
        }
    }

    func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        if isSending {
            isSending = false
            operationStatus = nil
            notice = "已停止等待后续回复。已显示的内容会保留。"
        }
    }

    func closeCurrentSession() async {
        guard !isSending else { return }
        guard let database else {
            notice = "本地数据库不可用，无法总结。"
            return
        }
        let apiKey = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            notice = "请先在设置中填写 DeepSeek API Key。"
            return
        }

        operationStatus = "正在整理日记、记忆和长期状态…"
        do {
            closeSummary = try await deepSeekService.closeCurrentSession(
                apiKey: apiKey,
                database: database
            )
            selectedSessionID = nil
            loadLocalCache()
            notice = "本轮总结已完成，结果已写入本地资料。"
        } catch {
            notice = "结束并总结失败：\(error.localizedDescription)"
        }
        operationStatus = nil
    }

    func saveAPIKey() {
        do {
            try secureSettings.saveDeepSeekAPIKey(apiKeyText)
            backendStatus = BackendConnectionStatus(
                state: isDeepSeekConfigured ? .unknown : .fallback,
                baseURL: "api.deepseek.com",
                detail: isDeepSeekConfigured ? "Key 已保存，建议执行连接测试。" : "DeepSeek Key 已清除。",
                lastCheckedAt: nil
            )
            notice = isDeepSeekConfigured ? "DeepSeek API Key 已保存。" : "DeepSeek API Key 已清除。"
        } catch {
            notice = "保存 DeepSeek API Key 失败：\(error.localizedDescription)"
        }
    }

    func deleteAPIKey() {
        do {
            try secureSettings.deleteDeepSeekAPIKey()
            apiKeyText = ""
            backendStatus = BackendConnectionStatus(
                state: .unknown,
                baseURL: "api.deepseek.com",
                detail: "尚未配置 DeepSeek API Key。",
                lastCheckedAt: nil
            )
            notice = "DeepSeek API Key 已删除。"
        } catch {
            notice = "删除 DeepSeek API Key 失败：\(error.localizedDescription)"
        }
    }

    func testDeepSeekConnection() async {
        guard !isCheckingBackend else { return }
        let apiKey = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            notice = "请先填写 DeepSeek API Key。"
            return
        }

        isCheckingBackend = true
        backendStatus = BackendConnectionStatus(
            state: .checking,
            baseURL: "api.deepseek.com",
            detail: "正在直接检查 DeepSeek API…",
            lastCheckedAt: backendStatus.lastCheckedAt
        )
        do {
            _ = try await deepSeekService.testConnection(apiKey: apiKey)
            backendStatus = BackendConnectionStatus(
                state: .online,
                baseURL: "api.deepseek.com",
                detail: "DeepSeek 直连正常。",
                lastCheckedAt: Date()
            )
            notice = "DeepSeek 连接测试成功。"
        } catch {
            backendStatus = BackendConnectionStatus(
                state: .fallback,
                baseURL: "api.deepseek.com",
                detail: error.localizedDescription,
                lastCheckedAt: Date()
            )
            notice = "DeepSeek 连接测试失败：\(error.localizedDescription)"
        }
        isCheckingBackend = false
    }

    private func noticeForNextAction(_ nextAction: String, hasFollowUp: Bool) -> String? {
        if hasFollowUp {
            return "快速回应之后，已根据理解计划补充第二次回应。"
        }
        if nextAction.contains("failed") {
            return "快速回应已保留；后续理解或深入回应暂时失败。"
        }
        return nil
    }

    private func appendMessage(_ message: ChatMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        messages = bounded(messages)
    }

    private func bounded(_ source: [ChatMessage]) -> [ChatMessage] {
        Array(source.suffix(maxDisplayMessages))
    }

    private func finishSend(correlationID: String, success: Bool, error: String?) {
        SendInstrumentation.shared.recordPhase(.storeApplyFinished, correlationID: correlationID)
        SendInstrumentation.shared.endSend(correlationID, success: success, error: error)
        isSending = false
        operationStatus = nil
        sendTask = nil
    }
}
