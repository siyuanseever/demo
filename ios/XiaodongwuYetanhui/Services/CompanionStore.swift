import Foundation
import Combine
import OSLog

@MainActor
final class CompanionStore: ObservableObject {
    @Published var selectedCharacterID = "yoyo"
    @Published var messages: [ChatMessage] = []
    @Published var sessions: [SessionSummary] = []
    @Published var memories: [MemoryEntry] = []
    @Published var journals: [JournalEntry] = []
    @Published var stateProfiles: [StateProfile] = []
    @Published var snapshot = DashboardSnapshot()
    @Published var loadError: String?
    @Published var isSending = false
    @Published var chatNotice: String?
    @Published var backendStatus = BackendConnectionStatus()
    @Published var latestCheckIn: EmotionCheckIn?
    @Published var checkInResponse = "先选一个最靠近此刻感受的小怪兽。它不需要准确，只要能被你碰到一点点。"
    @Published var isChatCheckInVisible = false
    @Published var interactionOffers: [CompanionInteractionOffer] = CompanionFixtures.interactionOffers
    @Published var isMonsterCareGameVisible = false
    @Published var careMoments: [CareMoment] = []
    @Published var flowMoments: [FlowMoment] = []
    @Published var bailanDiaryEntries: [BailanDiaryEntry] = []
    @Published var latestRecommendation: CompanionRecommendation?
    @Published var isRecommendationVisible = false
    @Published var recommendationHistory: [CompanionRecommendation] = []
    @Published var isGroupMode = true
    @Published var sessionNotice: String?
    @Published var isBackendSyncing = false
    @Published var summarizingSessionID: String?
    @Published var latestCloseSummary: SessionCloseSummary?
    @Published var lastBackendSyncAt: Date?
    @Published var homeEncouragement = "你已经很努力了，慢慢来，一切都会好起来的。"
    @Published var homeEncouragementHint: HomeHint?
    @Published var isHomeEncouragementLiked = false
    @Published var starMapInsight = StarMapInsight.mock
    @Published var isFlowInsightRefreshing = false
    @Published var flowInsightNotice = "正在读取最近的记忆、总结和长期状态。"
    @Published var isLocalAIConfigured = false
    @Published var localAISettingsNotice: String?
    @Published var macBackendURL = ""
    @Published var isMacSyncTokenConfigured = false
    @Published var moodAnalytics: RemoteMoodAnalytics?
    @Published var isMoodRefreshing = false
    @Published var chatOperationStatus: String?
    @Published var latestUserAssessment: UserConversationAssessment?
    @Published var latestLiveAssistantMessage: ChatMessage?
    @Published var flowContext = FlowContext.empty
    @Published var flowRitualIntention: String? = nil
    @Published var todayPlanItems: [PlanItem] = []
    @Published var customDatabasePath = ""
    @Published var currentDatabasePath: String?

    private let chatService = ChatService()
    private let localDeepSeekService = LocalDeepSeekService()
    private let secureSettings = SecureSettingsStore.shared
    private let interactionService = InteractionService()
    private let recommendationService = RecommendationService()
    private let careMomentsStorageKey = "xiaolu.careMoments.v1"
    private let flowMomentsStorageKey = "sensen.flowMoments.v1"
    private let bailanDiaryStorageKey = "sensen.bailanDiaryEntries.v1"
    private let recommendationStorageKey = "xiaolu.recommendations.v1"
    private let todayPlanStorageKey = "sensen.todayPlanItems.v1"
    private let customDatabasePathKey = "sensen.customDatabasePath.v1"
    private var lastHomeEncouragementRefreshAt: Date?
    private var hasAttemptedFlowInsightLoad = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SensenStory",
        category: "conversation"
    )

    /// Maximum number of messages kept in memory for display.
    /// Older messages remain in SQLite and are re-fetched on session resume.
    private let maxDisplayMessages = 100

    /// Shared database connection reused across operations to avoid
    /// repeated sqlite3_open / sqlite3_close cycles.
    private var sharedDatabase: SQLiteDatabase?

    private func database() throws -> SQLiteDatabase {
        if let db = sharedDatabase { return db }
        let db = try SQLiteDatabase()
        sharedDatabase = db
        return db
    }

    /// Append a message and trim the array if it exceeds the display cap.
    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if message.role == .assistant {
            latestLiveAssistantMessage = message
        }
        if messages.count > maxDisplayMessages {
            messages.removeFirst(messages.count - maxDisplayMessages)
        }
    }

    var selectedCharacter: CompanionCharacter {
        character(id: selectedCharacterID) ?? CompanionFixtures.characters[0]
    }

    init() {
        fputs("[CompanionStore] init 开始\n", stderr)
        backendStatus.baseURL = chatService.backendURLDescription
        macBackendURL = UserDefaults.standard.string(forKey: "sensen.macBackendURL") ?? chatService.backendURLDescription
        customDatabasePath = UserDefaults.standard.string(forKey: customDatabasePathKey) ?? ""
        fputs("[CompanionStore] customDatabasePath: \(customDatabasePath)\n", stderr)
        let apiKey = secureSettings.deepSeekAPIKey()
        isLocalAIConfigured = apiKey?.isEmpty == false
        fputs("[CompanionStore] isLocalAIConfigured: \(isLocalAIConfigured)\n", stderr)
        isMacSyncTokenConfigured = secureSettings.macSyncToken()?.isEmpty == false
        careMoments = loadCareMoments()
        flowMoments = loadFlowMoments()
        bailanDiaryEntries = loadBailanDiaryEntries()
        recommendationHistory = loadRecommendations()
        latestRecommendation = recommendationHistory.first
        todayPlanItems = loadTodayPlanItems()
        messages = [Self.greetingMessage(characterID: selectedCharacterID)]
        load()
        #if targetEnvironment(macCatalyst)
        if isLocalAIConfigured, let apiKey = apiKey {
            fputs("[CompanionStore] 启动 DeepSeek 连接测试...\n", stderr)
            Task {
                await testLocalDeepSeekConnection(apiKey: apiKey)
                if ProcessInfo.processInfo.environment["SENSEN_AUTO_TEST"] == "1" {
                    fputs("[CompanionStore] 自动测试模式启用，跳过自动发送（避免写入测试数据）\n", stderr)
                }
            }
        }
        #endif
        fputs("[CompanionStore] init 结束\n", stderr)
    }

    #if targetEnvironment(macCatalyst)
    private func testLocalDeepSeekConnection(apiKey: String) async {
        fputs("[CompanionStore] testLocalDeepSeekConnection 开始\n", stderr)
        do {
            let result = try await localDeepSeekService.testConnection(apiKey: apiKey)
            fputs("[CompanionStore] DeepSeek 连接测试成功: \(result)\n", stderr)
            logger.info("DeepSeek 连接测试成功")
        } catch {
            fputs("[CompanionStore] DeepSeek 连接测试失败: \(error)\n", stderr)
            logger.error("DeepSeek 连接测试失败: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    func load() {
        do {
            let database = try database()
            currentDatabasePath = database.path
            sessions = database.sessions()
            memories = database.memories()
            journals = database.journals()
            stateProfiles = database.stateProfiles()
            starMapInsight = database.latestStarMapInsight() ?? .mock
            snapshot = DashboardSnapshot(
                sessionCount: database.count(table: "sessions"),
                messageCount: database.count(table: "messages"),
                memoryCount: database.count(table: "memories"),
                journalCount: database.count(table: "journals")
            )
            loadError = nil
        } catch {
            loadError = "暂时没有读到本地数据库，先进入原型体验。"
            currentDatabasePath = nil
            sessions = []
            memories = []
            journals = []
            stateProfiles = []
            if messages.isEmpty {
                messages = [Self.greetingMessage(characterID: selectedCharacterID)]
            }
        }
        buildFlowContext()
        refreshInteractionOffers()
    }

    func buildFlowContext() {
        let dontCare = UserDefaults.standard
            .string(forKey: "bailan.dontCareItems")?
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        flowContext = FlowContext(
            id: UUID().uuidString,
            primaryGoal: starMapInsight.primaryGoalTitle,
            emotionWeather: starMapInsight.recentEmotionSummary,
            recentPattern: starMapInsight.recentPatternTitle,
            gentleReminder: starMapInsight.gentleReminder,
            dontCareItems: dontCare,
            todayPlanItems: todayPlanItems,
            latestBailanDiary: bailanDiaryEntries.first,
            latestFlowMoment: flowMoments.first
        )
    }

    func fetchOrGenerateStarMapInsight(forceRefresh: Bool = false) async -> StarMapInsight {
        do {
            let database = try SQLiteDatabase()
            if
                !forceRefresh,
                let cached = database.latestStarMapInsight(),
                Self.isDateInCurrentWeek(cached.generatedAt),
                !cached.isMockInsight
            {
                return cached
            }

            let generatedInsight: StarMapInsight
            if isLocalAIConfigured, let apiKey = secureSettings.deepSeekAPIKey(), !apiKey.isEmpty {
                generatedInsight = try await localDeepSeekService.generateWeeklyFlowInsight(
                    apiKey: apiKey,
                    database: database
                )
            } else {
                generatedInsight = try await chatService.fetchStarMapInsight()
            }
            database.saveStarMapInsight(generatedInsight)
            return generatedInsight
        } catch {
            if let database = try? SQLiteDatabase(), let cached = database.latestStarMapInsight() {
                return cached
            }
            return .mock
        }
    }

    func refreshStarMapInsight(forceRefresh: Bool = false) async {
        guard !isFlowInsightRefreshing else { return }
        if !forceRefresh {
            hasAttemptedFlowInsightLoad = true
        }
        isFlowInsightRefreshing = true
        flowInsightNotice = forceRefresh ? "正在重新提炼心流导航..." : "正在检查本周心流导航..."
        let insight = await fetchOrGenerateStarMapInsight(forceRefresh: forceRefresh)
        starMapInsight = insight
        buildFlowContext()
        flowInsightNotice = insight.isMockInsight
            ? "暂时没有取得真实分析，当前仅显示结构占位。"
            : "本周导航已根据记忆、单次总结、近期情绪和长期状态生成。"
        isFlowInsightRefreshing = false
    }

    func loadStarMapInsightIfNeeded() async {
        hasAttemptedFlowInsightLoad = true
        await refreshStarMapInsight()
    }

    private static func isDateInCurrentWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.weekOfYear, .yearForWeekOfYear]
        return calendar.dateComponents(components, from: date)
            == calendar.dateComponents(components, from: Date())
    }

    func openSession(_ sessionID: String) {
        latestLiveAssistantMessage = nil
        chatService.useSession(sessionID)
        localDeepSeekService.useSession(sessionID)
        do {
            let db = try database()
            let loadedMessages = db.messages(sessionID: sessionID)
            if loadedMessages.isEmpty {
                messages = [Self.greetingMessage(characterID: selectedCharacterID)]
                sessionNotice = "正在从 Mac 后端拉取历史会话…"
                chatNotice = nil
                Task {
                    await syncSessionFromBackend(sessionID)
                    let syncedMessages = (try? database().messages(sessionID: sessionID)) ?? []
                    if !syncedMessages.isEmpty {
                        messages = Array(syncedMessages.suffix(maxDisplayMessages))
                    }
                }
            } else {
                messages = Array(loadedMessages.suffix(maxDisplayMessages))
                sessionNotice = "已打开历史会话。继续发送时会进入当前夜谈。"
                chatNotice = nil
            }
        } catch {
            sessionNotice = "暂时无法打开这个会话：\(Self.describe(error))"
        }
    }

    func deleteSession(_ sessionID: String) {
        do {
            let db = try database()
            db.deleteSession(sessionID)
            if localDeepSeekService.currentSessionID == sessionID {
                localDeepSeekService.clearSession()
            }
            // Reload only sessions + snapshot — skip full load()
            sessions = db.sessions()
            snapshot = DashboardSnapshot(
                sessionCount: db.count(table: "sessions"),
                messageCount: db.count(table: "messages"),
                memoryCount: db.count(table: "memories"),
                journalCount: db.count(table: "journals")
            )
            if messages.contains(where: { $0.id == sessionID }) {
                messages = [Self.greetingMessage(characterID: selectedCharacterID)]
            }
            sessionNotice = "会话已删除。"
        } catch {
            sessionNotice = "删除失败：\(Self.describe(error))"
        }
    }

    func sendDraft(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        fputs("[sendDraft] 收到消息，字符数: \(trimmed.count), isSending: \(isSending)\n", stderr)
        guard !trimmed.isEmpty, !isSending else { return }
        await sendChatText(trimmed, fallbackReply: nil, shouldSuggestCheckIn: true)
    }

    func startNewSession() {
        latestLiveAssistantMessage = nil
        chatService.resetSession()
        localDeepSeekService.resetSession()
        messages = [Self.greetingMessage(characterID: selectedCharacterID)]
        latestCloseSummary = nil
        sessionNotice = "已经准备好一个新的夜谈。"
        chatNotice = nil
        latestUserAssessment = nil
        refreshInteractionOffers()
    }

    func saveDeepSeekAPIKey(_ apiKey: String) {
        do {
            try secureSettings.saveDeepSeekAPIKey(apiKey)
            isLocalAIConfigured = secureSettings.deepSeekAPIKey()?.isEmpty == false
            localAISettingsNotice = isLocalAIConfigured
                ? "API Key 已保存在这台设备的系统钥匙串中。"
                : "API Key 已清除。"
        } catch {
            localAISettingsNotice = error.localizedDescription
        }
    }

    func clearDeepSeekAPIKey() {
        do {
            try secureSettings.deleteDeepSeekAPIKey()
            isLocalAIConfigured = false
            localAISettingsNotice = "API Key 已从这台设备移除。"
        } catch {
            localAISettingsNotice = error.localizedDescription
        }
    }

    func saveCustomDatabasePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sessionNotice = "请输入有效的数据库路径。"
            return
        }
        let url = URL(fileURLWithPath: trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else {
            sessionNotice = "指定的数据库文件不存在：\(trimmed)"
            return
        }
        UserDefaults.standard.set(trimmed, forKey: customDatabasePathKey)
        customDatabasePath = trimmed
        sessionNotice = "数据库路径已保存，重启 App 后生效。"
    }

    func resetDatabasePath() {
        UserDefaults.standard.removeObject(forKey: customDatabasePathKey)
        customDatabasePath = ""
        sessionNotice = "已重置为默认数据库路径，重启 App 后生效。"
    }

    func saveMacBackendURL(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            sessionNotice = "请输入完整的 Mac 地址，例如 http://192.168.1.20:8765。"
            return
        }
        UserDefaults.standard.set(value, forKey: "sensen.macBackendURL")
        macBackendURL = value
        chatService.updateBaseURL(url)
        backendStatus = BackendConnectionStatus(
            state: .unknown,
            baseURL: value,
            detail: "Mac 地址已保存。请在同一局域网内点击同步。",
            lastCheckedAt: nil
        )
        sessionNotice = "Mac 局域网地址已保存。"
    }

    func saveMacSyncToken(_ rawValue: String) {
        do {
            try secureSettings.saveMacSyncToken(rawValue)
            isMacSyncTokenConfigured = secureSettings.macSyncToken()?.isEmpty == false
            sessionNotice = isMacSyncTokenConfigured
                ? "Mac 同步令牌已保存在系统钥匙串。"
                : "Mac 同步令牌已清除。"
        } catch {
            sessionNotice = error.localizedDescription
        }
    }

    @discardableResult
    func closeCurrentSession() async -> Bool {
        guard !isSending else { return false }
        isSending = true
        sessionNotice = "正在结束并总结这次夜谈..."
        do {
            let summary: SessionCloseSummary
            if isLocalAIConfigured, let apiKey = secureSettings.deepSeekAPIKey() {
                summary = try await localDeepSeekService.closeCurrentSession(
                    apiKey: apiKey,
                    database: try database()
                )
            } else {
                summary = try await chatService.closeCurrentSession()
            }
            sessionNotice = isLocalAIConfigured
                ? summary.journalSummary
                : "已总结：新增或处理 \(summary.memoryCount) 条记忆，长期状态更新 \(summary.stateProfileCount) 条。"
            if !isLocalAIConfigured {
                await syncAllFromBackend(forceStarMapRefresh: true)
            }
            load()
            latestCloseSummary = summary
            appendMessage(
                ChatMessage(
                    id: UUID().uuidString,
                    role: .system,
                    content: "会话总结：\(summary.journalSummary)",
                    characterID: nil,
                    createdAt: ""
                )
            )
            isSending = false
            return true
        } catch {
            sessionNotice = "暂时无法结束会话：\(Self.describe(error))"
            isSending = false
            return false
        }
    }

    func summarizeHistoricalSession(_ sessionID: String) async -> SessionCloseSummary? {
        let trimmedID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, summarizingSessionID == nil else { return nil }

        summarizingSessionID = trimmedID
        sessionNotice = "正在整理这次历史会话..."
        defer { summarizingSessionID = nil }

        do {
            let summary = try await chatService.summarizeSession(trimmedID)
            sessionNotice = "历史会话已整理：形成 \(summary.memoryCount) 条记忆，更新 \(summary.stateProfileCount) 条长期状态。"
            await syncAllFromBackend(forceStarMapRefresh: true)
            load()
            return summary
        } catch {
            sessionNotice = "暂时无法整理这次历史会话：\(Self.describe(error))"
            return nil
        }
    }

    func syncAllFromBackend(forceStarMapRefresh: Bool = false) async {
        guard !isBackendSyncing else { return }
        isBackendSyncing = true
        defer { isBackendSyncing = false }

        guard let database = try? SQLiteDatabase() else {
            sessionNotice = "暂时无法打开手机本地数据库。"
            backendStatus = BackendConnectionStatus(
                state: .fallback,
                baseURL: chatService.backendURLDescription,
                detail: "手机本地数据库暂时无法打开，已停止本次同步。",
                lastCheckedAt: Date()
            )
            return
        }
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst prototype runs on the same machine as the Python backend.
        // It only needs to pull from localhost; no phone-to-Mac upload token is required.
        #else
        guard let syncToken = secureSettings.macSyncToken(), !syncToken.isEmpty else {
            sessionNotice = "请先在设置中填写 Mac 同步令牌。"
            return
        }

        do {
            try await chatService.uploadSyncBundle(
                database.makeSyncUploadBundle(),
                token: syncToken
            )
        } catch {
            sessionNotice = "手机数据上传到 Mac 失败：\(error.localizedDescription)"
            backendStatus = BackendConnectionStatus(
                state: .fallback,
                baseURL: chatService.backendURLDescription,
                detail: sessionNotice ?? "双向同步失败。",
                lastCheckedAt: Date()
            )
            return
        }
        #endif

        async let fetchedSessions = try? chatService.fetchSessions()
        async let fetchedMessages = try? chatService.fetchMessages()
        async let fetchedMemories = try? chatService.fetchMemories()
        async let fetchedJournals = try? chatService.fetchJournals()
        async let fetchedProfiles = try? chatService.fetchStateProfiles()
        let (remoteSessions, remoteMessages, remoteMemories, remoteJournals, remoteProfiles) = await (
            fetchedSessions,
            fetchedMessages,
            fetchedMemories,
            fetchedJournals,
            fetchedProfiles
        )

        if let remoteSessions {
            for session in remoteSessions {
                database.upsertRemoteSession(session)
            }
        }
        if let remoteMessages {
            database.upsertRemoteMessages(remoteMessages)
        }
        if let remoteMemories {
            database.upsertRemoteMemories(remoteMemories)
        }
        if let remoteJournals {
            database.upsertRemoteJournals(remoteJournals)
        }
        if let remoteProfiles {
            database.upsertRemoteStateProfiles(remoteProfiles)
        }

        let shouldRefreshStarMap = forceStarMapRefresh
            || database.latestStarMapInsight().map {
                $0.isMockInsight
                    || !Calendar.current.isDate($0.generatedAt, equalTo: Date(), toGranularity: .month)
            } ?? true
        if shouldRefreshStarMap, let insight = try? await chatService.fetchStarMapInsight() {
            database.saveStarMapInsight(insight)
        }

        load()
        let successfulKinds = [
            remoteSessions != nil,
            remoteMessages != nil,
            remoteMemories != nil,
            remoteJournals != nil,
            remoteProfiles != nil,
        ].filter { $0 }.count
        let checkedAt = Date()
        if successfulKinds > 0 {
            lastBackendSyncAt = checkedAt
            let isComplete = successfulKinds == 5
            #if targetEnvironment(macCatalyst)
            sessionNotice = isComplete
                ? "已从本机后端刷新会话、消息、记忆、总结和长期画像。"
                : "已从本机后端刷新部分数据。"
            #else
            sessionNotice = isComplete
                ? "已同步会话消息、记忆、总结和长期画像。"
                : "部分数据暂时未同步，已保留手机上的最近缓存。"
            #endif
            backendStatus = BackendConnectionStatus(
                state: .online,
                baseURL: chatService.backendURLDescription,
                detail: isComplete ? "本机后端数据已刷新。" : "本机后端在线，但有部分数据暂时没有拉取成功。",
                lastCheckedAt: checkedAt
            )
        } else {
            sessionNotice = "暂时连不上 Mac，继续使用手机上的最近缓存。"
            backendStatus = BackendConnectionStatus(
                state: .fallback,
                baseURL: chatService.backendURLDescription,
                detail: "本次没有从 Mac 拉取到新数据，手机缓存仍可查看。",
                lastCheckedAt: checkedAt
            )
        }
    }

    func syncIfNeeded() async {
        // Local-first mode never contacts the Mac automatically.
    }

    func syncSessionFromBackend(_ sessionID: String) async {
        do {
            let detail = try await chatService.fetchSessionDetail(sessionID: sessionID)
            let database = try SQLiteDatabase()
            if let firstMessage = detail.messages.first {
                database.upsertRemoteSession(
                    RemoteSessionSummary(
                        id: detail.sessionID,
                        createdAt: firstMessage.createdAt,
                        endedAt: ""
                    )
                )
            }
            database.upsertRemoteMessages(detail.messages)
            load()
        } catch {
            sessionNotice = "暂时无法同步这个会话：\(Self.describe(error))"
        }
    }

    func checkBackendConnection() async {
        backendStatus = BackendConnectionStatus(
            state: .checking,
            baseURL: chatService.backendURLDescription,
            detail: "正在检查本地 Web 后端...",
            lastCheckedAt: backendStatus.lastCheckedAt
        )
        backendStatus = await chatService.checkConnection()
        if backendStatus.isOnline {
            await syncAllFromBackend()
        }
    }

    func refreshMoodAnalytics() async {
        guard !isMoodRefreshing else { return }
        isMoodRefreshing = true
        defer { isMoodRefreshing = false }
        do {
            let analytics = try await chatService.fetchMoodAnalytics()
            moodAnalytics = analytics
        } catch {
            // 保持上次缓存，静默失败
        }
    }

    func saveEmotionCheckIn(monster: EmotionMonster, intensity: Double, note: String) {
        let completion = interactionService.checkIn(monster: monster, intensity: intensity, note: note)
        latestCheckIn = completion.checkIn
        checkInResponse = completion.response
        recordCareMoment(completion.careMoment)
        refreshInteractionOffers()
    }

    func refreshInteractionOffers() {
        interactionOffers = interactionService.offers(
            latestCheckIn: latestCheckIn,
            journals: journals,
            messages: messages
        )
    }

    func acceptInteractionOffer(_ offer: CompanionInteractionOffer) async {
        if offer.kind == .checkIn {
            requestChatEmotionCheckIn()
            return
        }
        if offer.kind == .tinyGame {
            requestMonsterCareGame()
            return
        }
        if offer.kind == .recommendation {
            requestRecommendation()
            return
        }
        await sendChatText(
            offer.prompt,
            fallbackReply: offer.fallbackReply,
            shouldSuggestCheckIn: false
        )
    }

    func dismissInteractionOffer(_ offer: CompanionInteractionOffer) {
        guard interactionOffers.count > 1 else { return }
        interactionOffers.removeAll { $0.id == offer.id }
    }

    func refreshHomeEncouragement(force: Bool = false) async {
        let now = Date()
        if
            !force,
            let lastHomeEncouragementRefreshAt,
            now.timeIntervalSince(lastHomeEncouragementRefreshAt) < 6 * 60 * 60
        {
            return
        }
        lastHomeEncouragementRefreshAt = now
        do {
            let hint = try await chatService.homeHint()
            let text = hint.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                homeEncouragement = text
                homeEncouragementHint = hint
                isHomeEncouragementLiked = hint.liked
            }
        } catch {
            // Keep the bundled fallback when the local backend is unavailable.
        }
    }

    func toggleHomeEncouragementLike() {
        guard let hint = homeEncouragementHint else {
            isHomeEncouragementLiked.toggle()
            return
        }
        let nextValue = !isHomeEncouragementLiked
        isHomeEncouragementLiked = nextValue
        let updatedHint = HomeHint(
            id: hint.id,
            text: hint.text,
            source: hint.source,
            liked: nextValue,
            context: hint.context
        )
        homeEncouragementHint = updatedHint
        Task {
            do {
                try await chatService.sendHomeHintFeedback(updatedHint, liked: nextValue)
            } catch {
                // Keep the UI response immediate; the next refresh can resync with the backend.
            }
        }
    }

    func requestChatEmotionCheckIn() {
        isChatCheckInVisible = true
    }

    func dismissChatEmotionCheckIn() {
        isChatCheckInVisible = false
    }

    func requestMonsterCareGame() {
        isMonsterCareGameVisible = true
    }

    func dismissMonsterCareGame() {
        isMonsterCareGameVisible = false
    }

    func requestRecommendation(preferredMedium: RecommendationMedium? = nil) {
        let existingIDs = Set(recommendationHistory.map(\.id))
        let completion = recommendationService.recommendation(
            preferredMedium: preferredMedium,
            latestCheckIn: latestCheckIn,
            journals: journals,
            messages: messages,
            excluding: existingIDs
        )
        latestRecommendation = completion.recommendation
        isRecommendationVisible = true
        recordRecommendation(completion.recommendation)
    }

    func dismissRecommendation() {
        isRecommendationVisible = false
    }

    func sendRecommendationToChat() async {
        guard let latestRecommendation else { return }
        let recommendation = recommendationService.completion(for: latestRecommendation)
        isRecommendationVisible = false
        await sendChatText(
            recommendation.prompt,
            fallbackReply: recommendation.fallbackReply,
            shouldSuggestCheckIn: false
        )
    }

    func completeMonsterCareGame(
        monster: EmotionMonster,
        action: MonsterCareAction,
        safePlace: MonsterSafePlace,
        customName: String,
        note: String
    ) async {
        let completion = interactionService.monsterCare(
            monster: monster,
            action: action,
            safePlace: safePlace,
            customName: customName,
            note: note
        )
        isMonsterCareGameVisible = false
        recordCareMoment(completion.careMoment)
        await sendChatText(
            completion.prompt,
            fallbackReply: completion.fallbackReply,
            shouldSuggestCheckIn: false
        )
    }

    func completeChatEmotionCheckIn(monster: EmotionMonster, intensity: Double, note: String) async {
        let completion = interactionService.checkIn(monster: monster, intensity: intensity, note: note)
        latestCheckIn = completion.checkIn
        checkInResponse = completion.response
        recordCareMoment(completion.careMoment)
        refreshInteractionOffers()
        isChatCheckInVisible = false
        await sendChatText(
            completion.prompt,
            fallbackReply: completion.response,
            shouldSuggestCheckIn: false
        )
    }

    func character(id: String?) -> CompanionCharacter? {
        CompanionFixtures.character(id: id)
    }

    func recordFlowMoment(intention: String, ending: String) {
        let cleanIntention = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIntention.isEmpty else { return }
        flowMoments.insert(
            FlowMoment(
                id: UUID().uuidString,
                intention: cleanIntention,
                ending: ending,
                createdAt: Date()
            ),
            at: 0
        )
        if flowMoments.count > 12 {
            flowMoments = Array(flowMoments.prefix(12))
        }
        saveFlowMoments()
        buildFlowContext()
    }

    func triggerFlowRitual(intention: String) {
        flowRitualIntention = intention
    }

    func dismissFlowRitual() {
        flowRitualIntention = nil
    }

    func recordBailanDiary(content: String, response: String) {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return }
        bailanDiaryEntries.insert(
            BailanDiaryEntry(
                id: UUID().uuidString,
                content: cleanContent,
                response: response,
                createdAt: Date()
            ),
            at: 0
        )
        if bailanDiaryEntries.count > 24 {
            bailanDiaryEntries = Array(bailanDiaryEntries.prefix(24))
        }
        saveBailanDiaryEntries()
        buildFlowContext()
    }

    private func recordCareMoment(_ careMoment: CareMoment) {
        careMoments.insert(careMoment, at: 0)
        if careMoments.count > 8 {
            careMoments = Array(careMoments.prefix(8))
        }
        saveCareMoments()
    }

    private func recordRecommendation(_ recommendation: CompanionRecommendation) {
        recommendationHistory.removeAll { $0.id == recommendation.id }
        recommendationHistory.insert(recommendation, at: 0)
        if recommendationHistory.count > 8 {
            recommendationHistory = Array(recommendationHistory.prefix(8))
        }
        saveRecommendations()
    }

    private func loadCareMoments() -> [CareMoment] {
        guard let data = UserDefaults.standard.data(forKey: careMomentsStorageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([CareMoment].self, from: data)
        } catch {
            return []
        }
    }

    private func saveCareMoments() {
        do {
            let data = try JSONEncoder().encode(careMoments)
            UserDefaults.standard.set(data, forKey: careMomentsStorageKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: careMomentsStorageKey)
        }
    }

    private func loadFlowMoments() -> [FlowMoment] {
        guard let data = UserDefaults.standard.data(forKey: flowMomentsStorageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([FlowMoment].self, from: data)) ?? []
    }

    private func saveFlowMoments() {
        do {
            let data = try JSONEncoder().encode(flowMoments)
            UserDefaults.standard.set(data, forKey: flowMomentsStorageKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: flowMomentsStorageKey)
        }
    }

    private func loadBailanDiaryEntries() -> [BailanDiaryEntry] {
        if let data = UserDefaults.standard.data(forKey: bailanDiaryStorageKey),
           let entries = try? JSONDecoder().decode([BailanDiaryEntry].self, from: data) {
            return entries
        }

        let legacyEntry = UserDefaults.standard
            .string(forKey: "bailan.latestDiary")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !legacyEntry.isEmpty else { return [] }
        let migratedEntries = [
            BailanDiaryEntry(
                id: UUID().uuidString,
                content: legacyEntry,
                response: "嗯，先放这儿",
                createdAt: Date()
            )
        ]
        if let data = try? JSONEncoder().encode(migratedEntries) {
            UserDefaults.standard.set(data, forKey: bailanDiaryStorageKey)
        }
        return migratedEntries
    }

    private func saveBailanDiaryEntries() {
        guard let data = try? JSONEncoder().encode(bailanDiaryEntries) else { return }
        UserDefaults.standard.set(data, forKey: bailanDiaryStorageKey)
    }

    private func loadRecommendations() -> [CompanionRecommendation] {
        guard let data = UserDefaults.standard.data(forKey: recommendationStorageKey) else {
            return []
        }
        do {
            let recommendations = try JSONDecoder().decode([CompanionRecommendation].self, from: data)
            return recommendations.map(normalizedRecommendation)
        } catch {
            return []
        }
    }

    private func normalizedRecommendation(_ recommendation: CompanionRecommendation) -> CompanionRecommendation {
        let creator = recommendation.creator == "皮ico·艾尔" ? "皮科·艾尔" : recommendation.creator
        return CompanionRecommendation(
            id: recommendation.id,
            medium: recommendation.medium,
            title: recommendation.title,
            creator: creator,
            reason: recommendation.reason,
            practice: recommendation.practice,
            tintHex: recommendation.tintHex,
            createdAt: recommendation.createdAt
        )
    }

    private func saveRecommendations() {
        do {
            let data = try JSONEncoder().encode(recommendationHistory)
            UserDefaults.standard.set(data, forKey: recommendationStorageKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: recommendationStorageKey)
        }
    }

    private func loadTodayPlanItems() -> [PlanItem] {
        guard let data = UserDefaults.standard.data(forKey: todayPlanStorageKey) else {
            return defaultTodayPlanItems()
        }
        do {
            return try JSONDecoder().decode([PlanItem].self, from: data)
        } catch {
            return defaultTodayPlanItems()
        }
    }

    func saveTodayPlanItems() {
        guard let data = try? JSONEncoder().encode(todayPlanItems) else { return }
        UserDefaults.standard.set(data, forKey: todayPlanStorageKey)
    }

    private func defaultTodayPlanItems() -> [PlanItem] {
        [
            PlanItem(id: "plan-1", title: "起床", isDone: false),
            PlanItem(id: "plan-2", title: "活着", isDone: false),
            PlanItem(id: "plan-3", title: "其他", isDone: false),
        ]
    }

    private func sendChatText(
        _ text: String,
        fallbackReply: String?,
        shouldSuggestCheckIn: Bool
    ) async {
        guard !text.isEmpty, !isSending else { return }
        let character = selectedCharacter
        let correlationID = SendInstrumentation.shared.beginSend(
            messageLength: text.utf8.count,
            isGroupMode: isGroupMode
        )
        SendInstrumentation.shared.recordPhase(.sendTaskStarted, correlationID: correlationID)
        appendMessage(
            ChatMessage(
                id: UUID().uuidString,
                role: .user,
                content: text,
                characterID: nil,
                createdAt: ""
            )
        )
        latestUserAssessment = nil
        isSending = true
        chatNotice = nil
        chatOperationStatus = "正在连接本机后端…"
        logger.info("[\(correlationID, privacy: .public)] chat request started mode=\(self.isGroupMode ? "auto" : "manual", privacy: .public)")

        let apiKey = secureSettings.deepSeekAPIKey()
        fputs("[sendChatText] API Key configured: \(apiKey?.isEmpty == false)\n", stderr)
        if let apiKey, !apiKey.isEmpty {
            fputs("[sendChatText] 进入本地 DeepSeek 模式\n", stderr)
            await sendLocalChatText(
                text,
                character: character,
                apiKey: apiKey,
                fallbackReply: fallbackReply,
                shouldSuggestCheckIn: shouldSuggestCheckIn,
                correlationID: correlationID
            )
            return
        }

        await sendBackendChatText(
            text,
            character: character,
            fallbackReply: fallbackReply,
            shouldSuggestCheckIn: shouldSuggestCheckIn,
            correlationID: correlationID
        )
    }

    private func sendBackendChatText(
        _ text: String,
        character: CompanionCharacter,
        fallbackReply: String?,
        shouldSuggestCheckIn: Bool,
        correlationID: String
    ) async {
        SendInstrumentation.shared.recordPhase(.requestEncodeStarted, correlationID: correlationID)
        let streamResult = await chatService.sendStreaming(
            text: text,
            character: character,
            isGroupMode: true,
            fallbackReply: fallbackReply,
            correlationID: correlationID
        ) { [weak self] update in
            self?.applyStreamUpdate(update)
        }
        let response = streamResult.response
        latestUserAssessment = response.assessment ?? latestUserAssessment
        SendInstrumentation.shared.recordPhase(.storeApplyStarted, correlationID: correlationID)
        if streamResult.deliveredStageCount == 0 {
            appendAssistantResponse(response, fallbackCharacter: character)
        } else if let responseCharacter = self.character(id: response.characterID) {
            selectedCharacterID = responseCharacter.id
        }
        chatOperationStatus = nil
        logger.info(
            "chat request completed stages=\(streamResult.deliveredStageCount, privacy: .public) fallback=\(response.usedFallback, privacy: .public)"
        )
        if let errorDetail = response.errorDetail, !errorDetail.isEmpty {
            logger.error("chat request detail: \(errorDetail, privacy: .public)")
        }
        backendStatus = BackendConnectionStatus(
            state: response.usedFallback ? .fallback : .online,
            baseURL: response.backendURL,
            detail: response.usedFallback
                ? "这轮消息使用了 iOS 原型回复：\(response.errorDetail ?? "未知错误")"
                : "这轮消息来自本地 Python 服务。",
            lastCheckedAt: Date()
        )
        chatNotice = response.notice
        isChatCheckInVisible = shouldSuggestCheckIn && interactionService.shouldSuggestEmotionCheckIn(from: text + " " + response.reply)
        refreshInteractionOffers()
        isSending = false
        SendInstrumentation.shared.recordPhase(.storeApplyFinished, correlationID: correlationID)
        SendInstrumentation.shared.endSend(correlationID, success: !response.usedFallback)
    }

    private func applyStreamUpdate(_ update: ChatServiceStreamUpdate) {
        if let assessment = update.response.assessment {
            latestUserAssessment = assessment
        }
        if let cid = update.correlationID {
            if update.stage == .quick {
                SendInstrumentation.shared.recordPhase(.firstResponseReceived, correlationID: cid)
            }
        }
        switch update.stage {
        case .quick:
            chatOperationStatus = "已收到快速回应，正在继续识别意图并深入理解…"
            logger.info("chat quick reply received")
        case .deep:
            chatOperationStatus = "深度回应已生成，正在收尾…"
            logger.info("chat deep reply received")
        }
        appendAssistantResponse(
            update.response,
            fallbackCharacter: selectedCharacter,
            replyStage: update.stage == .quick ? "quick" : "deep"
        )
    }

    private func appendAssistantResponse(
        _ response: ChatServiceResponse,
        fallbackCharacter: CompanionCharacter,
        replyStage: String = ""
    ) {
        if response.groupMessages.isEmpty {
            if let responseCharacter = self.character(id: response.characterID) {
                selectedCharacterID = responseCharacter.id
            }
            appendMessage(
                ChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: response.reply,
                    characterID: response.characterID ?? fallbackCharacter.id,
                    createdAt: "",
                    expressionID: response.expressionID ?? "",
                    replyStage: replyStage,
                    routeSummary: response.routeSummary,
                    knowledgeCards: response.knowledgeCards,
                    retrievedMemories: response.retrievedMemories
                )
            )
            return
        }

        for (index, groupMessage) in response.groupMessages.enumerated() {
            appendMessage(
                ChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: groupMessage.text,
                    characterID: groupMessage.characterID ?? response.characterID ?? fallbackCharacter.id,
                    createdAt: "",
                    groupRole: groupMessage.role,
                    action: groupMessage.action,
                    expressionID: groupMessage.expressionID ?? response.expressionID ?? "",
                    replyStage: replyStage,
                    routeSummary: index == 0 ? response.routeSummary : nil,
                    knowledgeCards: groupMessage.knowledgeCards,
                    retrievedMemories: response.retrievedMemories
                )
            )
        }
        if let responseCharacter = self.character(id: response.characterID) {
            selectedCharacterID = responseCharacter.id
        }
    }

    private func sendLocalChatText(
        _ text: String,
        character: CompanionCharacter,
        apiKey: String,
        fallbackReply: String?,
        shouldSuggestCheckIn: Bool,
        correlationID: String
    ) async {
        fputs("[sendLocalChatText] 开始, correlationID: \(correlationID)\n", stderr)
        SendInstrumentation.shared.recordPhase(.requestEncodeStarted, correlationID: correlationID)
        chatOperationStatus = "正在直接连接 DeepSeek…"
        do {
            let database = try database()
            fputs("[sendLocalChatText] 数据库打开成功, path: \(database.path)\n", stderr)
            let result = try await localDeepSeekService.send(
                text: text,
                character: character,
                apiKey: apiKey,
                database: database
            ) { quickReply in
                self.appendMessage(quickReply)
                SendInstrumentation.shared.recordPhase(.firstResponseReceived, correlationID: correlationID)
                self.chatOperationStatus = "已收到快速回应，后台正在规划下一步…"
                fputs("[sendLocalChatText] 快速回复已添加到UI\n", stderr)
            }
            fputs("[sendLocalChatText] send 成功, quick: \(result.quickReply != nil), next_action: \(result.nextAction), follow_up: \(result.followUpReply != nil)\n", stderr)
            latestUserAssessment = result.assessment
            SendInstrumentation.shared.recordPhase(.storeApplyStarted, correlationID: correlationID)
            if let followUpReply = result.followUpReply {
                appendMessage(followUpReply)
            }
            switch result.nextAction {
            case "quick_only":
                chatNotice = "这一轮即时回应已经足够，后台没有追加深度回复。"
            case "quick_only_plan_failed":
                chatNotice = "即时回应已经显示，但后台规划暂时没有完成。"
            case "quick_only_deep_failed":
                chatNotice = "即时回应已经显示，但后续深度回复暂时没有完成。"
            default:
                chatNotice = "本地模式：直接连接 DeepSeek。"
            }
            backendStatus = BackendConnectionStatus(
                state: .online,
                baseURL: "DeepSeek API",
                detail: "这轮消息通过本地 DeepSeek API 直接生成。",
                lastCheckedAt: Date()
            )
            // Update snapshot only — avoid full reload
            if let db = sharedDatabase {
                snapshot = DashboardSnapshot(
                    sessionCount: db.count(table: "sessions"),
                    messageCount: db.count(table: "messages"),
                    memoryCount: db.count(table: "memories"),
                    journalCount: db.count(table: "journals")
                )
            }
            buildFlowContext()
            refreshInteractionOffers()
            logger.info("[\(correlationID, privacy: .public)] local chat completed")
            fputs("[sendLocalChatText] 完成\n", stderr)
        } catch {
            fputs("[sendLocalChatText] 失败: \(error)\n", stderr)
            let fallback = fallbackReply ?? "这一轮暂时没有成功连接 DeepSeek。你刚才写下的话已经保存在手机上，可以稍后再试。"
            let fallbackMessage = ChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: fallback,
                characterID: character.id,
                createdAt: "",
                expressionID: character.defaultExpressionID
            )
            appendMessage(fallbackMessage)
            chatNotice = error.localizedDescription
            backendStatus = BackendConnectionStatus(
                state: .fallback,
                baseURL: "DeepSeek API",
                detail: "本地 DeepSeek 调用失败：\(error.localizedDescription)",
                lastCheckedAt: Date()
            )
            logger.error("[\(correlationID, privacy: .public)] local chat failed: \(error.localizedDescription, privacy: .public)")
        }
        chatOperationStatus = nil
        isChatCheckInVisible = shouldSuggestCheckIn
            && interactionService.shouldSuggestEmotionCheckIn(from: text + " " + (messages.last?.content ?? ""))
        refreshInteractionOffers()
        isSending = false
        SendInstrumentation.shared.recordPhase(.storeApplyFinished, correlationID: correlationID)
        let failed = chatNotice?.contains("失败") ?? false
        SendInstrumentation.shared.endSend(correlationID, success: !failed)
    }

    private static func greetingMessage(characterID: String) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: "晚上好。我在这里。你可以先说一点点，不需要整理好。",
            characterID: characterID,
            createdAt: ""
        )
    }

    private static func describe(_ error: Error) -> String {
        return error.localizedDescription
    }
}
