import Foundation

struct ChatServiceResponse {
    let sessionID: String?
    let reply: String
    let characterID: String?
    let expressionID: String?
    let groupMessages: [ChatServiceGroupMessage]
    let knowledgeCards: [KnowledgeCard]
    let routeSummary: String?
    let usedFallback: Bool
    let notice: String?
    let backendURL: String
    let errorDetail: String?
}

struct ChatServiceStreamUpdate {
    enum Stage {
        case quick
        case deep
    }

    let stage: Stage
    let response: ChatServiceResponse
    let correlationID: String?
}

struct ChatServiceStreamResult {
    let response: ChatServiceResponse
    let deliveredStageCount: Int
}

struct ChatServiceGroupMessage {
    let role: String
    let text: String
    let action: String
    let characterID: String?
    let expressionID: String?
    let knowledgeCards: [KnowledgeCard]
}

struct SessionCloseJournal {
    let summary: String
    let emotionCurve: [String]
    let keywords: [String]
    let insights: [String]
    let suggestedNextStep: String
    let moodScore: Int
    let dominantEmotion: String
}

struct SessionCloseMemory: Identifiable {
    let id: String
    let category: String
    let subcategory: String
    let content: String
    let keywords: [String]
    let action: String
    let reason: String
    let confidence: Double
    let importance: Int
}

struct SessionCloseStateProfile: Identifiable {
    var id: String { domain }
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String
    let action: String
    let reason: String
}

struct SessionCloseSummary: Identifiable {
    let id = UUID()
    let journalSummary: String
    let memoryCount: Int
    let stateProfileCount: Int
    let journal: SessionCloseJournal?
    let memories: [SessionCloseMemory]
    let stateProfiles: [SessionCloseStateProfile]

    init(
        journalSummary: String,
        memoryCount: Int,
        stateProfileCount: Int,
        journal: SessionCloseJournal? = nil,
        memories: [SessionCloseMemory] = [],
        stateProfiles: [SessionCloseStateProfile] = []
    ) {
        self.journalSummary = journalSummary
        self.memoryCount = memoryCount
        self.stateProfileCount = stateProfileCount
        self.journal = journal
        self.memories = memories
        self.stateProfiles = stateProfiles
    }
}

struct HomeHint {
    let id: String
    let text: String
    let source: String
    let liked: Bool
    let context: [String: [String]]
}

struct RemoteSessionSummary {
    let id: String
    let createdAt: String
    let endedAt: String
}

struct RemoteSessionDetail {
    let sessionID: String
    let messages: [RemoteChatMessage]
}

struct RemoteChatMessage {
    let id: String
    let sessionID: String
    let role: String
    let content: String
    let model: String
    let createdAt: String
    let characterID: String
    let groupRole: String
    let action: String
    let expressionID: String
    let knowledgeCardIDs: [String]
    let routePlan: SyncRoutePlanRecord?
}

struct RemoteMemory {
    let id: String
    let userID: String
    let category: String
    let subcategory: String
    let keywords: [String]
    let status: String
    let content: String
    let evidence: String
    let confidence: Double
    let importance: Int
    let sourceSessionID: String
    let createdAt: String
    let updatedAt: String
}

struct RemoteJournal {
    let id: String
    let sessionID: String
    let summary: String
    let emotionCurve: [String]
    let keywords: [String]
    let insights: [String]
    let suggestedNextStep: String
    let moodScore: Int
    let dominantEmotion: String
    let createdAt: String
}

struct RemoteStateProfile {
    let id: String
    let userID: String
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String
    let sourceSessionID: String
    let createdAt: String
    let updatedAt: String
}

struct SyncUploadBundle: Encodable {
    let sessions: [SyncSessionRecord]
    let messages: [SyncMessageRecord]
    let memories: [SyncMemoryRecord]
    let journals: [SyncJournalRecord]
    let stateProfiles: [SyncStateProfileRecord]

    enum CodingKeys: String, CodingKey {
        case sessions
        case messages
        case memories
        case journals
        case stateProfiles = "state_profiles"
    }
}

struct SyncSessionRecord: Encodable {
    let id: String
    let createdAt: String
    let endedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case endedAt = "ended_at"
    }
}

struct SyncMessageRecord: Encodable {
    let id: String
    let sessionID: String
    let role: String
    let content: String
    let model: String?
    let metadata: SyncMessageMetadata
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case role
        case content
        case model
        case metadata
        case createdAt = "created_at"
    }
}

struct SyncMessageMetadata: Encodable {
    let characterID: String?
    let groupRole: String?
    let action: String?
    let expressionID: String?
    let knowledgeCardIDs: [String]
    let routePlan: SyncRoutePlanRecord?

    enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case groupRole = "group_role"
        case action
        case expressionID = "expression_id"
        case knowledgeCardIDs = "knowledge_card_ids"
        case routePlan = "route_plan"
    }
}

struct SyncRoutePlanRecord: Codable {
    let userState: String
    let coreNeed: String
    let riskLevel: String
    let responseMode: String
    let characterID: String
    let expressionID: String
    let knowledgeNeeds: [String]
    let memoryQueries: [String]
    let knowledgeQueries: [String]
    let responseGuidance: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case userState = "user_state"
        case coreNeed = "core_need"
        case riskLevel = "risk_level"
        case responseMode = "response_mode"
        case characterID = "character_id"
        case expressionID = "expression_id"
        case knowledgeNeeds = "knowledge_needs"
        case memoryQueries = "memory_queries"
        case knowledgeQueries = "knowledge_queries"
        case responseGuidance = "response_guidance"
        case reason
    }

    init?(dictionary: [String: Any]?) {
        guard
            let dictionary,
            let characterID = dictionary["character_id"] as? String,
            !characterID.isEmpty
        else {
            return nil
        }
        userState = dictionary["user_state"] as? String ?? ""
        coreNeed = dictionary["core_need"] as? String ?? ""
        riskLevel = dictionary["risk_level"] as? String ?? "low"
        responseMode = dictionary["response_mode"] as? String ?? "mixed"
        self.characterID = characterID
        expressionID = dictionary["expression_id"] as? String ?? ""
        knowledgeNeeds = dictionary["knowledge_needs"] as? [String] ?? []
        memoryQueries = dictionary["memory_queries"] as? [String] ?? []
        knowledgeQueries = dictionary["knowledge_queries"] as? [String] ?? []
        responseGuidance = dictionary["response_guidance"] as? String ?? ""
        reason = dictionary["reason"] as? String ?? ""
    }

    var dictionary: [String: Any] {
        [
            "user_state": userState,
            "core_need": coreNeed,
            "risk_level": riskLevel,
            "response_mode": responseMode,
            "character_id": characterID,
            "expression_id": expressionID,
            "knowledge_needs": knowledgeNeeds,
            "memory_queries": memoryQueries,
            "knowledge_queries": knowledgeQueries,
            "response_guidance": responseGuidance,
            "reason": reason,
        ]
    }
}

struct SyncMemoryRecord: Encodable {
    let id: String
    let userID: String
    let category: String
    let subcategory: String
    let keywords: [String]
    let status: String
    let content: String
    let evidence: String
    let confidence: Double
    let importance: Int
    let sourceSessionID: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case category
        case subcategory
        case keywords
        case status
        case content
        case evidence
        case confidence
        case importance
        case sourceSessionID = "source_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SyncJournalRecord: Encodable {
    let id: String
    let sessionID: String
    let summary: String
    let emotionCurve: [String]
    let keywords: [String]
    let insights: [String]
    let suggestedNextStep: String
    let moodScore: Int?
    let dominantEmotion: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case summary
        case emotionCurve = "emotion_curve"
        case keywords
        case insights
        case suggestedNextStep = "suggested_next_step"
        case moodScore = "mood_score"
        case dominantEmotion = "dominant_emotion"
        case createdAt = "created_at"
    }
}

struct SyncStateProfileRecord: Encodable {
    let id: String
    let userID: String
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String
    let sourceSessionID: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case domain
        case stage
        case summary
        case intensity
        case trend
        case confidence
        case evidence
        case supportStrategy = "support_strategy"
        case sourceSessionID = "source_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

final class ChatService {
    private var baseURL: URL
    private let session: URLSession
    private var sessionID: String?

    init(
        baseURL: URL = ChatService.defaultBaseURL(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    var backendURLDescription: String {
        baseURL.absoluteString
    }

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    func checkConnection() async -> BackendConnectionStatus {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/health"))
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            let _: EmptyResponseBody = try await decode(request)
            return BackendConnectionStatus(
                state: .online,
                baseURL: backendURLDescription,
                detail: "本地后端在线。iOS 会在发送第一句话时再创建会话。",
                lastCheckedAt: Date()
            )
        } catch {
            return BackendConnectionStatus(
                state: .fallback,
                baseURL: backendURLDescription,
                detail: "暂时连不上本地后端：\(Self.describe(error))",
                lastCheckedAt: Date()
            )
        }
    }

    func send(
        text: String,
        character: CompanionCharacter,
        isGroupMode: Bool = false,
        fallbackReply: String? = nil
    ) async -> ChatServiceResponse {
        do {
            let sessionID = try await currentSessionID()
            let request = try makeJSONRequest(
                path: "/api/chat",
                body: ChatRequestBody(
                    sessionID: sessionID,
                    text: text,
                    characterID: isGroupMode ? "auto" : character.id
                )
            )
            let response: ChatResponseBody = try await decode(request)
            return makeResponse(sessionID: sessionID, body: response, fallbackCharacter: character)
        } catch {
            return ChatServiceResponse(
                sessionID: nil,
                reply: fallbackReply ?? Self.fallbackReply(for: text, character: character),
                characterID: character.id,
                expressionID: character.defaultExpressionID,
                groupMessages: [],
                knowledgeCards: [],
                routeSummary: nil,
                usedFallback: true,
                notice: "本地 Web 服务暂时没有回应，先用 iOS 原型陪你接住这一轮。",
                backendURL: backendURLDescription,
                errorDetail: Self.describe(error)
            )
        }
    }

    func sendStreaming(
        text: String,
        character: CompanionCharacter,
        isGroupMode: Bool = false,
        fallbackReply: String? = nil,
        correlationID: String = "",
        onUpdate: @escaping (ChatServiceStreamUpdate) async -> Void
    ) async -> ChatServiceStreamResult {
        var deliveredStageCount = 0
        var latestResponse: ChatServiceResponse?

        do {
            let sessionID = try await currentSessionID()
            var request = try makeJSONRequest(
                path: "/api/chat_stream",
                body: ChatRequestBody(
                    sessionID: sessionID,
                    text: text,
                    characterID: isGroupMode ? "auto" : character.id
                )
            )
            request.timeoutInterval = 90
            if !correlationID.isEmpty {
                request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-ID")
            }

            if !correlationID.isEmpty {
                DispatchQueue.main.async {
                    SendInstrumentation.shared.recordPhase(.requestResumed, correlationID: correlationID)
                }
            }
            let (bytes, urlResponse) = try await session.bytes(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw ChatServiceError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ChatServiceError.httpStatus(httpResponse.statusCode)
            }

            var eventType = "message"
            var dataLines: [String] = []
            streamLoop: for try await line in bytes.lines {
                if line.hasPrefix("event:") {
                    eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if line.hasPrefix("data:") {
                    dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                    continue
                }
                guard line.isEmpty, !dataLines.isEmpty else { continue }

                let currentEventType = eventType
                let data = Data(dataLines.joined(separator: "\n").utf8)
                eventType = "message"
                dataLines.removeAll(keepingCapacity: true)

                switch currentEventType {
                case "quick_reply":
                    let body = try JSONDecoder().decode(QuickReplyResponseBody.self, from: data)
                    let response = ChatServiceResponse(
                        sessionID: sessionID,
                        reply: body.text,
                        characterID: body.character?.id ?? character.id,
                        expressionID: body.expression?.id ?? character.defaultExpressionID,
                        groupMessages: [],
                        knowledgeCards: [],
                        routeSummary: nil,
                        usedFallback: false,
                        notice: nil,
                        backendURL: backendURLDescription,
                        errorDetail: nil
                    )
                    latestResponse = response
                    deliveredStageCount += 1
                    await onUpdate(ChatServiceStreamUpdate(stage: .quick, response: response, correlationID: correlationID))
                case "deep_reply":
                    let body = try JSONDecoder().decode(ChatResponseBody.self, from: data)
                    let response = makeResponse(sessionID: sessionID, body: body, fallbackCharacter: character)
                    latestResponse = response
                    deliveredStageCount += 1
                    await onUpdate(ChatServiceStreamUpdate(stage: .deep, response: response, correlationID: correlationID))
                case "final":
                    let body = try JSONDecoder().decode(ChatResponseBody.self, from: data)
                    latestResponse = makeResponse(sessionID: sessionID, body: body, fallbackCharacter: character)
                case "error":
                    let body = try JSONDecoder().decode(StreamErrorResponseBody.self, from: data)
                    throw ChatServiceError.stream(body.error)
                case "done":
                    break streamLoop
                default:
                    continue
                }
            }

            guard let latestResponse else {
                throw ChatServiceError.invalidResponse
            }
            return ChatServiceStreamResult(
                response: latestResponse,
                deliveredStageCount: deliveredStageCount
            )
        } catch {
            if let latestResponse {
                return ChatServiceStreamResult(
                    response: ChatServiceResponse(
                        sessionID: latestResponse.sessionID,
                        reply: latestResponse.reply,
                        characterID: latestResponse.characterID,
                        expressionID: latestResponse.expressionID,
                        groupMessages: latestResponse.groupMessages,
                        knowledgeCards: latestResponse.knowledgeCards,
                        routeSummary: latestResponse.routeSummary,
                        usedFallback: false,
                        notice: "快速回应已显示，但后续分析没有完成。",
                        backendURL: backendURLDescription,
                        errorDetail: Self.describe(error)
                    ),
                    deliveredStageCount: deliveredStageCount
                )
            }
            return ChatServiceStreamResult(
                response: ChatServiceResponse(
                    sessionID: nil,
                    reply: fallbackReply ?? Self.fallbackReply(for: text, character: character),
                    characterID: character.id,
                    expressionID: character.defaultExpressionID,
                    groupMessages: [],
                    knowledgeCards: [],
                    routeSummary: nil,
                    usedFallback: true,
                    notice: "本地后端暂时没有完成这轮回复，已使用原型兜底。",
                    backendURL: backendURLDescription,
                    errorDetail: Self.describe(error)
                ),
                deliveredStageCount: deliveredStageCount
            )
        }
    }

    func closeCurrentSession() async throws -> SessionCloseSummary {
        guard let sessionID else {
            throw ChatServiceError.noActiveSession
        }
        let summary = try await summarizeSession(sessionID)
        self.sessionID = nil
        return summary
    }

    func summarizeSession(_ sessionID: String) async throws -> SessionCloseSummary {
        let request = try makeJSONRequest(path: "/api/end", body: EndSessionRequestBody(sessionID: sessionID))
        let response: EndSessionResponseBody = try await decode(request)
        return SessionCloseSummary(
            journalSummary: response.journal.summary,
            memoryCount: response.memories.count,
            stateProfileCount: response.stateProfiles.filter { $0.action != "no_change" }.count,
            journal: response.journal.closeJournal,
            memories: response.memories.map(\.closeMemory),
            stateProfiles: response.stateProfiles.map(\.closeStateProfile)
        )
    }

    func resetSession() {
        sessionID = nil
    }

    func useSession(_ sessionID: String) {
        self.sessionID = sessionID
    }

    func fetchSessions(limit: Int = 200) async throws -> [RemoteSessionSummary] {
        let url = try url(path: "/api/data", queryItems: [
            URLQueryItem(name: "type", value: "sessions"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        let response: RemoteSessionsResponseBody = try await decode(request)
        return response.items.map(\.remoteSession)
    }

    func fetchSessionDetail(sessionID: String) async throws -> RemoteSessionDetail {
        let url = try url(path: "/api/session_detail", queryItems: [
            URLQueryItem(name: "id", value: sessionID),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let response: RemoteSessionDetailResponseBody = try await decode(request)
        return response.remoteDetail(sessionID: sessionID)
    }

    func fetchMessages(limit: Int = 2000) async throws -> [RemoteChatMessage] {
        let response: RemoteMessagesResponseBody = try await fetchData(type: "messages", limit: limit)
        return response.items.map(\.remoteMessage)
    }

    func fetchMemories(limit: Int = 500) async throws -> [RemoteMemory] {
        let response: RemoteMemoriesResponseBody = try await fetchData(type: "memories", limit: limit)
        return response.items.map(\.remoteMemory)
    }

    func fetchJournals(limit: Int = 300) async throws -> [RemoteJournal] {
        let response: RemoteJournalsResponseBody = try await fetchData(type: "journals", limit: limit)
        return response.items.map(\.remoteJournal)
    }

    func fetchStateProfiles() async throws -> [RemoteStateProfile] {
        let response: RemoteStateProfilesResponseBody = try await fetchData(type: "state")
        return response.items.compactMap { $0.current?.remoteStateProfile }
    }

    func fetchMoodAnalytics() async throws -> RemoteMoodAnalytics {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/mood_analytics"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let response: RemoteMoodAnalyticsResponseBody = try await decode(request)
        return response.analytics
    }

    func uploadSyncBundle(_ bundle: SyncUploadBundle, token: String) async throws {
        let normalizedPath = "api/sync/merge"
        var request = URLRequest(url: baseURL.appendingPathComponent(normalizedPath))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Sensen-Sync-Token")
        request.httpBody = try JSONEncoder().encode(bundle)
        let _: SyncMergeResponseBody = try await decode(request)
    }

    func homeHint() async throws -> HomeHint {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/home_hint"))
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        let response: HomeHintResponseBody = try await decode(request)
        return HomeHint(
            id: response.id,
            text: response.text,
            source: response.source,
            liked: response.liked,
            context: response.context
        )
    }

    func sendHomeHintFeedback(_ hint: HomeHint, liked: Bool) async throws {
        let request = try makeJSONRequest(
            path: "/api/home_hint_feedback",
            body: HomeHintFeedbackRequestBody(
                hintID: hint.id,
                text: hint.text,
                liked: liked,
                source: hint.source,
                context: hint.context
            )
        )
        let _: EmptyResponseBody = try await decode(request)
    }

    func fetchStarMapInsight() async throws -> StarMapInsight {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/star_map_insight"))
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        let response: StarMapInsightResponseBody = try await decode(request)
        return response.starMapInsight
    }

    private func currentSessionID() async throws -> String {
        if let sessionID {
            return sessionID
        }
        let request = try makeJSONRequest(path: "/api/session", body: EmptyBody())
        let response: SessionResponseBody = try await decode(request)
        sessionID = response.sessionID
        return response.sessionID
    }

    private func makeJSONRequest<Body: Encodable>(path: String, body: Body) throws -> URLRequest {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: baseURL.appendingPathComponent(normalizedPath))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(url: baseURL.appendingPathComponent(normalizedPath), resolvingAgainstBaseURL: false) else {
            throw ChatServiceError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ChatServiceError.invalidResponse
        }
        return url
    }

    private func fetchData<Response: Decodable>(type: String, limit: Int? = nil) async throws -> Response {
        var queryItems = [URLQueryItem(name: "type", value: type)]
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        let url = try url(path: "/api/data", queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        return try await decode(request)
    }

    private func decode<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw ChatServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ChatServiceError.httpStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func makeResponse(
        sessionID: String,
        body: ChatResponseBody,
        fallbackCharacter: CompanionCharacter
    ) -> ChatServiceResponse {
        let knowledgeCards = body.knowledgeCards.map(\.knowledgeCard)
        let groupMessages = body.groupMessages ?? []
        let cardTargetIndex = groupMessages.firstIndex {
            $0.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "main"
        } ?? max(0, groupMessages.count - 1)
        return ChatServiceResponse(
            sessionID: sessionID,
            reply: body.reply,
            characterID: body.character?.id ?? fallbackCharacter.id,
            expressionID: body.expression?.id ?? body.routePlan?.expressionID,
            groupMessages: groupMessages.enumerated().map { index, item in
                ChatServiceGroupMessage(
                    role: item.role,
                    text: item.text,
                    action: item.action ?? "",
                    characterID: item.character?.id,
                    expressionID: item.expression?.id ?? item.expressionID,
                    knowledgeCards: index == cardTargetIndex ? knowledgeCards : []
                )
            },
            knowledgeCards: knowledgeCards,
            routeSummary: Self.routeSummary(body.routePlan),
            usedFallback: false,
            notice: nil,
            backendURL: backendURLDescription,
            errorDetail: nil
        )
    }

    private static func fallbackReply(for text: String, character: CompanionCharacter) -> String {
        if text.contains("累") || text.contains("撑不住") {
            return "\(character.name)听见你已经很累了。我们先不急着解决，先把今晚最重的一块放到桌面上。"
        }
        if text.contains("为什么") || text.contains("复盘") {
            return "\(character.name)可以陪你一起看结构。先从一个具体场景开始，会比直接审判自己更稳。"
        }
        return "\(character.name)在这里接住这一小段。你愿意的话，可以继续说：这件事最刺痛你的地方是什么？"
    }

    private static func routeSummary(_ plan: RoutePlanResponseBody?) -> String? {
        guard let plan else { return nil }
        if let characterID = plan.characterID {
            let character = CompanionFixtures.character(id: characterID)
            let name = character?.name ?? "森森兔"
            let expressionID = plan.expressionID ?? character?.defaultExpressionID ?? ""
            let expressionLabel = character?.expression(id: expressionID)?.label ?? expressionID
            let mode = plan.responseMode.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
            if let reason = plan.reason, !reason.isEmpty {
                return "本轮规划\(mode)：\(name) · \(expressionLabel)；\(reason)"
            }
            return "本轮规划\(mode)：\(name) · \(expressionLabel)"
        }
        guard let mainID = plan.main?.characterID else { return nil }
        let empathyID = plan.empathy?.characterID ?? plan.empathic?.characterID
        let needID = plan.need?.characterID ?? plan.pinpoint?.characterID
        let anchorID = plan.anchor?.characterID
        let empathyName = CompanionFixtures.character(id: empathyID)?.name ?? "一只小动物"
        let needName = CompanionFixtures.character(id: needID)?.name ?? "另一只小动物"
        let mainName = CompanionFixtures.character(id: mainID)?.name ?? "主回应"
        let anchorName = anchorID.flatMap { id in CompanionFixtures.character(id: id)?.name }
        let mode = plan.responseMode.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
        if let anchorName {
            return "本轮规划\(mode)：\(empathyName)共情，\(needName)点明需求，\(mainName)主回复，\(anchorName)收束"
        }
        return "本轮规划\(mode)：\(empathyName)共情，\(needName)点明需求，\(mainName)主回复"
    }

    private static func defaultBaseURL() -> URL {
        if
            let rawValue = ProcessInfo.processInfo.environment["XIAOLU_BACKEND_URL"],
            let url = URL(string: rawValue)
        {
            return url
        }
        
        // 检查是否是模拟器
        #if targetEnvironment(simulator)
            return URL(string: "http://127.0.0.1:8765")!
        #else
            if
                let rawValue = UserDefaults.standard.string(forKey: "sensen.macBackendURL"),
                let url = URL(string: rawValue)
            {
                return url
            }
            return URL(string: "http://127.0.0.1:8765")!
        #endif
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? ChatServiceError {
            return error.description
        }
        let nsError = error as NSError
        return nsError.localizedDescription
    }
}

private struct EmptyBody: Encodable {}

private struct EmptyResponseBody: Decodable {}

private struct SyncMergeResponseBody: Decodable {
    let ok: Bool
}

private struct SessionResponseBody: Decodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

private struct RemoteSessionsResponseBody: Decodable {
    let items: [RemoteSessionResponseBody]
}

private struct RemoteSessionResponseBody: Decodable {
    let id: String
    let createdAt: String
    let endedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case endedAt = "ended_at"
    }

    var remoteSession: RemoteSessionSummary {
        RemoteSessionSummary(
            id: id,
            createdAt: createdAt,
            endedAt: endedAt ?? ""
        )
    }
}

private struct RemoteSessionDetailResponseBody: Decodable {
    let messages: [RemoteMessageResponseBody]

    func remoteDetail(sessionID: String) -> RemoteSessionDetail {
        RemoteSessionDetail(
            sessionID: sessionID,
            messages: messages.map(\.remoteMessage)
        )
    }
}

private struct RemoteMessagesResponseBody: Decodable {
    let items: [RemoteMessageResponseBody]
}

private struct RemoteMessageResponseBody: Decodable {
    let id: String
    let sessionID: String
    let role: String
    let content: String
    let model: String?
    let createdAt: String
    let characterID: String?
    let groupRole: String?
    let action: String?
    let expressionID: String?
    let knowledgeCardIDs: [String]?
    let routePlan: SyncRoutePlanRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case role
        case content
        case model
        case createdAt = "created_at"
        case characterID = "character_id"
        case groupRole = "group_role"
        case action
        case expressionID = "expression_id"
        case knowledgeCardIDs = "knowledge_card_ids"
        case routePlan = "route_plan"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        characterID = try container.decodeIfPresent(String.self, forKey: .characterID)
        groupRole = try container.decodeIfPresent(String.self, forKey: .groupRole)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        expressionID = try container.decodeIfPresent(String.self, forKey: .expressionID)
        knowledgeCardIDs = try container.decodeIfPresent([String].self, forKey: .knowledgeCardIDs)
        // 容错：route_plan 可能是嵌套格式（多角色）或扁平格式（单角色），
        // 格式不匹配时设为 nil，避免毁掉整个消息列表的解码。
        routePlan = try? container.decode(SyncRoutePlanRecord.self, forKey: .routePlan)
    }

    var remoteMessage: RemoteChatMessage {
        RemoteChatMessage(
            id: id,
            sessionID: sessionID,
            role: role,
            content: content,
            model: model ?? "",
            createdAt: createdAt,
            characterID: characterID ?? "",
            groupRole: groupRole ?? "",
            action: action ?? "",
            expressionID: expressionID ?? "",
            knowledgeCardIDs: knowledgeCardIDs ?? [],
            routePlan: routePlan
        )
    }
}

private struct RemoteMemoriesResponseBody: Decodable {
    let items: [RemoteMemoryResponseBody]
}

private struct RemoteMemoryResponseBody: Decodable {
    let id: String
    let userID: String
    let category: String
    let subcategory: String
    let keywords: [String]
    let status: String
    let content: String
    let evidence: String
    let confidence: Double
    let importance: Int
    let sourceSessionID: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case category
        case subcategory
        case keywords
        case status
        case content
        case evidence
        case confidence
        case importance
        case sourceSessionID = "source_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var remoteMemory: RemoteMemory {
        RemoteMemory(
            id: id,
            userID: userID,
            category: category,
            subcategory: subcategory,
            keywords: keywords,
            status: status,
            content: content,
            evidence: evidence,
            confidence: confidence,
            importance: importance,
            sourceSessionID: sourceSessionID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct RemoteJournalsResponseBody: Decodable {
    let items: [RemoteJournalResponseBody]
}

private struct RemoteJournalResponseBody: Decodable {
    let id: String
    let sessionID: String
    let summary: String
    let emotionCurve: [String]
    let keywords: [String]
    let insights: [String]
    let suggestedNextStep: String
    let moodScore: Int?
    let dominantEmotion: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case summary
        case emotionCurve = "emotion_curve"
        case keywords
        case insights
        case suggestedNextStep = "suggested_next_step"
        case moodScore = "mood_score"
        case dominantEmotion = "dominant_emotion"
        case createdAt = "created_at"
    }

    var remoteJournal: RemoteJournal {
        RemoteJournal(
            id: id,
            sessionID: sessionID,
            summary: summary,
            emotionCurve: emotionCurve,
            keywords: keywords,
            insights: insights,
            suggestedNextStep: suggestedNextStep,
            moodScore: moodScore ?? 0,
            dominantEmotion: dominantEmotion,
            createdAt: createdAt
        )
    }
}

private struct RemoteStateProfilesResponseBody: Decodable {
    let items: [RemoteStateProfileOverviewResponseBody]
}

private struct RemoteStateProfileOverviewResponseBody: Decodable {
    let current: RemoteStateProfileResponseBody?
}

private struct RemoteStateProfileResponseBody: Decodable {
    let id: String
    let userID: String
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String
    let sourceSessionID: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case domain
        case stage
        case summary
        case intensity
        case trend
        case confidence
        case evidence
        case supportStrategy = "support_strategy"
        case sourceSessionID = "source_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var remoteStateProfile: RemoteStateProfile {
        RemoteStateProfile(
            id: id,
            userID: userID,
            domain: domain,
            stage: stage,
            summary: summary,
            intensity: intensity,
            trend: trend,
            confidence: confidence,
            evidence: evidence,
            supportStrategy: supportStrategy,
            sourceSessionID: sourceSessionID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct ChatRequestBody: Encodable {
    let sessionID: String
    let text: String
    let characterID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case text
        case characterID = "character_id"
    }
}

private struct ChatResponseBody: Decodable {
    let reply: String
    let character: ResponseCharacter?
    let expression: ResponseExpression?
    let groupMessages: [GroupMessageResponseBody]?
    let knowledgeCards: [KnowledgeCardResponseBody]
    let routePlan: RoutePlanResponseBody?

    enum CodingKeys: String, CodingKey {
        case reply
        case character
        case expression
        case groupMessages = "group_messages"
        case knowledgeCards = "knowledge_cards"
        case routePlan = "route_plan"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        character = try container.decodeIfPresent(ResponseCharacter.self, forKey: .character)
        expression = try container.decodeIfPresent(ResponseExpression.self, forKey: .expression)
        groupMessages = try container.decodeIfPresent([GroupMessageResponseBody].self, forKey: .groupMessages)
        knowledgeCards = try container.decodeIfPresent([KnowledgeCardResponseBody].self, forKey: .knowledgeCards) ?? []
        routePlan = try container.decodeIfPresent(RoutePlanResponseBody.self, forKey: .routePlan)
    }
}

private struct QuickReplyResponseBody: Decodable {
    let text: String
    let character: ResponseCharacter?
    let expression: ResponseExpression?
}

private struct StreamErrorResponseBody: Decodable {
    let error: String
}

private struct GroupMessageResponseBody: Decodable {
    let role: String
    let text: String
    let action: String?
    let character: ResponseCharacter?
    let expression: ResponseExpression?
    let expressionID: String?

    enum CodingKeys: String, CodingKey {
        case role
        case text
        case action
        case character
        case expression
        case expressionID = "expression_id"
    }
}

private struct ResponseCharacter: Decodable {
    let id: String
}

private struct ResponseExpression: Decodable {
    let id: String
}

private struct HomeHintResponseBody: Decodable {
    let id: String
    let text: String
    let source: String
    let liked: Bool
    let context: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case source
        case liked
        case context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decode(String.self, forKey: .text)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        liked = try container.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        context = try container.decodeIfPresent([String: [String]].self, forKey: .context) ?? [:]
    }
}

private struct StarMapInsightResponseBody: Decodable {
    let id: String
    let generatedAt: String
    let periodStart: String
    let periodEnd: String
    let primaryGoalTitle: String
    let primaryGoalReason: String
    let primaryGoalNextStep: String
    let primaryGoalChallenge: String
    let secondaryGoalTitle: String
    let secondaryGoalReason: String
    let secondaryGoalNextStep: String
    let secondaryGoalChallenge: String
    let recentEmotionSummary: String
    let recentEmotionTags: [String]
    let flowSupport: String
    let memoryCues: [String]
    let coreInsight: String
    let coreInsightDetail: String
    let recentPatternTitle: String
    let recentPatternItems: [String]
    let recentPatternDetail: String
    let flowConditionTitle: String
    let flowConditionItems: [String]
    let flowConditionDetail: String
    let gentleReminderTitle: String
    let gentleReminder: String
    let gentleReminderDetail: String
    let sourceSummary: String

    enum CodingKeys: String, CodingKey {
        case id
        case generatedAt = "generated_at"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case primaryGoalTitle = "primary_goal_title"
        case primaryGoalReason = "primary_goal_reason"
        case primaryGoalNextStep = "primary_goal_next_step"
        case primaryGoalChallenge = "primary_goal_challenge"
        case secondaryGoalTitle = "secondary_goal_title"
        case secondaryGoalReason = "secondary_goal_reason"
        case secondaryGoalNextStep = "secondary_goal_next_step"
        case secondaryGoalChallenge = "secondary_goal_challenge"
        case recentEmotionSummary = "recent_emotion_summary"
        case recentEmotionTags = "recent_emotion_tags"
        case flowSupport = "flow_support"
        case memoryCues = "memory_cues"
        case coreInsight = "core_insight"
        case coreInsightDetail = "core_insight_detail"
        case recentPatternTitle = "recent_pattern_title"
        case recentPatternItems = "recent_pattern_items"
        case recentPatternDetail = "recent_pattern_detail"
        case flowConditionTitle = "flow_condition_title"
        case flowConditionItems = "flow_condition_items"
        case flowConditionDetail = "flow_condition_detail"
        case gentleReminderTitle = "gentle_reminder_title"
        case gentleReminder = "gentle_reminder"
        case gentleReminderDetail = "gentle_reminder_detail"
        case sourceSummary = "source_summary"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        periodStart = try container.decodeIfPresent(String.self, forKey: .periodStart) ?? ""
        periodEnd = try container.decodeIfPresent(String.self, forKey: .periodEnd) ?? ""
        primaryGoalTitle = try container.decodeIfPresent(String.self, forKey: .primaryGoalTitle) ?? StarMapInsight.mock.primaryGoalTitle
        primaryGoalReason = try container.decodeIfPresent(String.self, forKey: .primaryGoalReason) ?? StarMapInsight.mock.primaryGoalReason
        primaryGoalNextStep = try container.decodeIfPresent(String.self, forKey: .primaryGoalNextStep) ?? StarMapInsight.mock.primaryGoalNextStep
        primaryGoalChallenge = try container.decodeIfPresent(String.self, forKey: .primaryGoalChallenge) ?? StarMapInsight.mock.primaryGoalChallenge
        secondaryGoalTitle = try container.decodeIfPresent(String.self, forKey: .secondaryGoalTitle) ?? ""
        secondaryGoalReason = try container.decodeIfPresent(String.self, forKey: .secondaryGoalReason) ?? ""
        secondaryGoalNextStep = try container.decodeIfPresent(String.self, forKey: .secondaryGoalNextStep) ?? ""
        secondaryGoalChallenge = try container.decodeIfPresent(String.self, forKey: .secondaryGoalChallenge) ?? ""
        recentEmotionSummary = try container.decodeIfPresent(String.self, forKey: .recentEmotionSummary) ?? StarMapInsight.mock.recentEmotionSummary
        recentEmotionTags = try container.decodeIfPresent([String].self, forKey: .recentEmotionTags) ?? StarMapInsight.mock.recentEmotionTags
        flowSupport = try container.decodeIfPresent(String.self, forKey: .flowSupport) ?? StarMapInsight.mock.flowSupport
        memoryCues = try container.decodeIfPresent([String].self, forKey: .memoryCues) ?? StarMapInsight.mock.memoryCues
        coreInsight = try container.decodeIfPresent(String.self, forKey: .coreInsight) ?? StarMapInsight.mock.coreInsight
        coreInsightDetail = try container.decodeIfPresent(String.self, forKey: .coreInsightDetail) ?? StarMapInsight.mock.coreInsightDetail
        recentPatternTitle = try container.decodeIfPresent(String.self, forKey: .recentPatternTitle) ?? StarMapInsight.mock.recentPatternTitle
        recentPatternItems = try container.decodeIfPresent([String].self, forKey: .recentPatternItems) ?? StarMapInsight.mock.recentPatternItems
        recentPatternDetail = try container.decodeIfPresent(String.self, forKey: .recentPatternDetail) ?? StarMapInsight.mock.recentPatternDetail
        flowConditionTitle = try container.decodeIfPresent(String.self, forKey: .flowConditionTitle) ?? StarMapInsight.mock.flowConditionTitle
        flowConditionItems = try container.decodeIfPresent([String].self, forKey: .flowConditionItems) ?? StarMapInsight.mock.flowConditionItems
        flowConditionDetail = try container.decodeIfPresent(String.self, forKey: .flowConditionDetail) ?? StarMapInsight.mock.flowConditionDetail
        gentleReminderTitle = try container.decodeIfPresent(String.self, forKey: .gentleReminderTitle) ?? StarMapInsight.mock.gentleReminderTitle
        gentleReminder = try container.decodeIfPresent(String.self, forKey: .gentleReminder) ?? StarMapInsight.mock.gentleReminder
        gentleReminderDetail = try container.decodeIfPresent(String.self, forKey: .gentleReminderDetail) ?? StarMapInsight.mock.gentleReminderDetail
        sourceSummary = try container.decodeIfPresent(String.self, forKey: .sourceSummary) ?? ""
    }

    var starMapInsight: StarMapInsight {
        StarMapInsight(
            id: id,
            generatedAt: Self.date(from: generatedAt) ?? Date(),
            periodStart: Self.date(from: periodStart) ?? Date(),
            periodEnd: Self.date(from: periodEnd) ?? Date(),
            primaryGoalTitle: primaryGoalTitle,
            primaryGoalReason: primaryGoalReason,
            primaryGoalNextStep: primaryGoalNextStep,
            primaryGoalChallenge: primaryGoalChallenge,
            secondaryGoalTitle: secondaryGoalTitle,
            secondaryGoalReason: secondaryGoalReason,
            secondaryGoalNextStep: secondaryGoalNextStep,
            secondaryGoalChallenge: secondaryGoalChallenge,
            recentEmotionSummary: recentEmotionSummary,
            recentEmotionTags: recentEmotionTags,
            flowSupport: flowSupport,
            memoryCues: memoryCues,
            coreInsight: coreInsight,
            coreInsightDetail: coreInsightDetail,
            recentPatternTitle: recentPatternTitle,
            recentPatternItems: recentPatternItems,
            recentPatternDetail: recentPatternDetail,
            flowConditionTitle: flowConditionTitle,
            flowConditionItems: flowConditionItems,
            flowConditionDetail: flowConditionDetail,
            gentleReminderTitle: gentleReminderTitle,
            gentleReminder: gentleReminder,
            gentleReminderDetail: gentleReminderDetail,
            sourceSummary: sourceSummary
        )
    }

    private static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct HomeHintFeedbackRequestBody: Encodable {
    let hintID: String
    let text: String
    let liked: Bool
    let source: String
    let context: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case hintID = "hint_id"
        case text
        case liked
        case source
        case context
    }
}

private struct KnowledgeCardResponseBody: Decodable {
    let id: String
    let title: String
    let concept: String?

    var knowledgeCard: KnowledgeCard {
        KnowledgeCard(id: id, title: title, concept: concept ?? "")
    }
}

private struct RoutePlanResponseBody: Decodable {
    let characterID: String?
    let expressionID: String?
    let reason: String?
    let responseMode: String?
    let empathy: RouteRoleResponseBody?
    let empathic: RouteRoleResponseBody?
    let need: RouteRoleResponseBody?
    let pinpoint: RouteRoleResponseBody?
    let main: RouteRoleResponseBody?
    let anchor: RouteRoleResponseBody?

    enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case expressionID = "expression_id"
        case reason
        case responseMode = "response_mode"
        case empathy
        case empathic
        case need
        case pinpoint
        case main
        case anchor
    }
}

private struct RouteRoleResponseBody: Decodable {
    let characterID: String

    enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
    }
}

private struct EndSessionRequestBody: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

private struct EndSessionResponseBody: Decodable {
    let journal: EndSessionJournalBody
    let memories: [EndSessionMemoryBody]
    let stateProfiles: [EndSessionStateProfileBody]

    enum CodingKeys: String, CodingKey {
        case journal
        case memories
        case stateProfiles = "state_profiles"
    }
}

private struct EndSessionJournalBody: Decodable {
    let summary: String
    let emotionCurve: [String]
    let keywords: [String]
    let insights: [String]
    let suggestedNextStep: String
    let moodScore: Int
    let dominantEmotion: String

    enum CodingKeys: String, CodingKey {
        case summary
        case emotionCurve = "emotion_curve"
        case keywords
        case insights
        case suggestedNextStep = "suggested_next_step"
        case moodScore = "mood_score"
        case dominantEmotion = "dominant_emotion"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        emotionCurve = try container.decodeIfPresent([String].self, forKey: .emotionCurve) ?? []
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        insights = try container.decodeIfPresent([String].self, forKey: .insights) ?? []
        suggestedNextStep = try container.decodeIfPresent(String.self, forKey: .suggestedNextStep) ?? ""
        moodScore = try container.decodeIfPresent(Int.self, forKey: .moodScore) ?? 0
        dominantEmotion = try container.decodeIfPresent(String.self, forKey: .dominantEmotion) ?? ""
    }

    var closeJournal: SessionCloseJournal {
        SessionCloseJournal(
            summary: summary,
            emotionCurve: emotionCurve,
            keywords: keywords,
            insights: insights,
            suggestedNextStep: suggestedNextStep,
            moodScore: moodScore,
            dominantEmotion: dominantEmotion
        )
    }
}

private struct EndSessionMemoryBody: Decodable {
    let id: String
    let category: String
    let subcategory: String
    let content: String
    let keywords: [String]
    let action: String
    let reason: String
    let confidence: Double
    let importance: Int

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case subcategory
        case content
        case keywords
        case action
        case reason
        case confidence
        case importance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "未分类"
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory) ?? "general"
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? "create"
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        importance = try container.decodeIfPresent(Int.self, forKey: .importance) ?? 0
    }

    var closeMemory: SessionCloseMemory {
        SessionCloseMemory(
            id: id,
            category: category,
            subcategory: subcategory,
            content: content,
            keywords: keywords,
            action: action,
            reason: reason,
            confidence: confidence,
            importance: importance
        )
    }
}

private struct EndSessionStateProfileBody: Decodable {
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String
    let action: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case domain
        case stage
        case summary
        case intensity
        case trend
        case confidence
        case evidence
        case supportStrategy = "support_strategy"
        case action
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decodeIfPresent(String.self, forKey: .domain) ?? "unknown"
        stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        intensity = try container.decodeIfPresent(Int.self, forKey: .intensity) ?? 0
        trend = try container.decodeIfPresent(String.self, forKey: .trend) ?? "unknown"
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        supportStrategy = try container.decodeIfPresent(String.self, forKey: .supportStrategy) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? "no_change"
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    var closeStateProfile: SessionCloseStateProfile {
        SessionCloseStateProfile(
            domain: domain,
            stage: stage,
            summary: summary,
            intensity: intensity,
            trend: trend,
            confidence: confidence,
            evidence: evidence,
            supportStrategy: supportStrategy,
            action: action,
            reason: reason
        )
    }
}

struct RemoteMoodAnalytics: Decodable {
    let points: [RemoteMoodPoint]
    let daily: [RemoteMoodDaily]
    let weekly: [RemoteMoodWeekly]
}

struct RemoteMoodPoint: Decodable {
    let id: String
    let sessionID: String
    let date: String
    let week: String
    let createdAt: String
    let score: Double
    let dominantEmotion: String
    let summary: String
    let keywords: [String]
    let emotionCurve: [String]
    let suggestedNextStep: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case date
        case week
        case createdAt = "created_at"
        case score
        case dominantEmotion = "dominant_emotion"
        case summary
        case keywords
        case emotionCurve = "emotion_curve"
        case suggestedNextStep = "suggested_next_step"
    }
}

struct RemoteMoodDaily: Decodable {
    let date: String
    let score: Double
    let count: Int
    let keywords: [String]
    let dominantEmotion: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case date
        case score
        case count
        case keywords
        case dominantEmotion = "dominant_emotion"
        case summary
    }
}

struct RemoteMoodWeekly: Decodable {
    let week: String
    let score: Double
    let count: Int
    let keywords: [String]
    let dominantEmotion: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case week
        case score
        case count
        case keywords
        case dominantEmotion = "dominant_emotion"
        case summary
    }
}

private struct RemoteMoodAnalyticsResponseBody: Decodable {
    let points: [RemoteMoodPoint]
    let daily: [RemoteMoodDaily]
    let weekly: [RemoteMoodWeekly]

    var analytics: RemoteMoodAnalytics {
        RemoteMoodAnalytics(points: points, daily: daily, weekly: weekly)
    }
}

private enum ChatServiceError: Error, CustomStringConvertible {
    case invalidResponse
    case httpStatus(Int)
    case noActiveSession
    case stream(String)

    var description: String {
        switch self {
        case .invalidResponse:
            return "后端响应格式无效"
        case .httpStatus(let status):
            return "HTTP \(status)"
        case .noActiveSession:
            return "还没有正在进行的会话"
        case .stream(let message):
            return "流式回复失败：\(message)"
        }
    }
}
