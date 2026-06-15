import Foundation
import Combine

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
    @Published var latestRecommendation: CompanionRecommendation?
    @Published var isRecommendationVisible = false
    @Published var recommendationHistory: [CompanionRecommendation] = []
    @Published var isGroupMode = true
    @Published var sessionNotice: String?

    private let chatService = ChatService()
    private let interactionService = InteractionService()
    private let recommendationService = RecommendationService()
    private let careMomentsStorageKey = "xiaolu.careMoments.v1"
    private let recommendationStorageKey = "xiaolu.recommendations.v1"

    var selectedCharacter: CompanionCharacter {
        character(id: selectedCharacterID) ?? CompanionFixtures.characters[0]
    }

    init() {
        backendStatus.baseURL = chatService.backendURLDescription
        careMoments = loadCareMoments()
        recommendationHistory = loadRecommendations()
        latestRecommendation = recommendationHistory.first
        messages = [Self.greetingMessage(characterID: selectedCharacterID)]
        load()
    }

    func load() {
        do {
            let database = try SQLiteDatabase()
            sessions = database.sessions()
            memories = database.memories()
            journals = database.journals()
            stateProfiles = database.stateProfiles()
            snapshot = DashboardSnapshot(
                sessionCount: database.count(table: "sessions"),
                messageCount: database.count(table: "messages"),
                memoryCount: database.count(table: "memories"),
                journalCount: database.count(table: "journals")
            )
            loadError = nil
        } catch {
            loadError = "暂时没有读到本地数据库，先进入原型体验。"
            sessions = []
            memories = []
            journals = []
            stateProfiles = []
            if messages.isEmpty {
                messages = [Self.greetingMessage(characterID: selectedCharacterID)]
            }
        }
        refreshInteractionOffers()
    }

    func openSession(_ sessionID: String) {
        do {
            let database = try SQLiteDatabase()
            let loadedMessages = database.messages(sessionID: sessionID)
            messages = loadedMessages.isEmpty ? [Self.greetingMessage(characterID: selectedCharacterID)] : loadedMessages
            sessionNotice = "已打开历史会话。继续发送时会进入当前夜谈。"
            chatNotice = nil
        } catch {
            sessionNotice = "暂时无法打开这个会话：\(Self.describe(error))"
        }
    }

    func sendDraft(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        await sendChatText(trimmed, fallbackReply: nil, shouldSuggestCheckIn: true)
    }

    func startNewSession() {
        chatService.resetSession()
        messages = [Self.greetingMessage(characterID: selectedCharacterID)]
        sessionNotice = "已经准备好一个新的夜谈。"
        chatNotice = nil
        refreshInteractionOffers()
    }

    func closeCurrentSession() async {
        guard !isSending else { return }
        isSending = true
        sessionNotice = "正在结束并总结这次夜谈..."
        do {
            let summary = try await chatService.closeCurrentSession()
            sessionNotice = "已总结：新增或处理 \(summary.memoryCount) 条记忆，长期状态更新 \(summary.stateProfileCount) 条。"
            load()
            messages.append(
                ChatMessage(
                    id: UUID().uuidString,
                    role: .system,
                    content: "会话总结：\(summary.journalSummary)",
                    characterID: nil,
                    createdAt: ""
                )
            )
        } catch {
            sessionNotice = "暂时无法结束会话：\(Self.describe(error))"
        }
        isSending = false
    }

    func checkBackendConnection() async {
        backendStatus = BackendConnectionStatus(
            state: .checking,
            baseURL: chatService.backendURLDescription,
            detail: "正在检查本地 Web 后端...",
            lastCheckedAt: backendStatus.lastCheckedAt
        )
        backendStatus = await chatService.checkConnection()
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

    private func sendChatText(
        _ text: String,
        fallbackReply: String?,
        shouldSuggestCheckIn: Bool
    ) async {
        guard !text.isEmpty, !isSending else { return }
        let character = selectedCharacter
        messages.append(
            ChatMessage(
                id: UUID().uuidString,
                role: .user,
                content: text,
                characterID: nil,
                createdAt: ""
            )
        )
        isSending = true
        chatNotice = nil
        let response = await chatService.send(
            text: text,
            character: character,
            isGroupMode: true,
            fallbackReply: fallbackReply
        )
        backendStatus = BackendConnectionStatus(
            state: response.usedFallback ? .fallback : .online,
            baseURL: response.backendURL,
            detail: response.usedFallback
                ? "这轮消息使用了 iOS 原型回复：\(response.errorDetail ?? "未知错误")"
                : "这轮消息来自本地 Web 后端。",
            lastCheckedAt: Date()
        )
        if response.groupMessages.isEmpty {
            if let responseCharacter = self.character(id: response.characterID) {
                selectedCharacterID = responseCharacter.id
            }
            messages.append(
                ChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: response.reply,
                    characterID: response.characterID ?? character.id,
                    createdAt: "",
                    expressionID: response.expressionID ?? "",
                    routeSummary: response.routeSummary,
                    knowledgeCards: response.knowledgeCards
                )
            )
        } else {
            for (index, groupMessage) in response.groupMessages.enumerated() {
                messages.append(
                    ChatMessage(
                        id: UUID().uuidString,
                        role: .assistant,
                        content: groupMessage.text,
                        characterID: groupMessage.characterID ?? response.characterID ?? character.id,
                        createdAt: "",
                        groupRole: groupMessage.role,
                        action: groupMessage.action,
                        expressionID: groupMessage.expressionID ?? response.expressionID ?? "",
                        routeSummary: index == 0 ? response.routeSummary : nil,
                        knowledgeCards: groupMessage.knowledgeCards
                    )
                )
            }
            if let responseCharacter = self.character(id: response.characterID) {
                selectedCharacterID = responseCharacter.id
            }
        }
        chatNotice = response.notice
        isChatCheckInVisible = shouldSuggestCheckIn && interactionService.shouldSuggestEmotionCheckIn(from: text + " " + response.reply)
        refreshInteractionOffers()
        isSending = false
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
