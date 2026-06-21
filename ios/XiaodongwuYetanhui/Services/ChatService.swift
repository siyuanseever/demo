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

struct ChatServiceGroupMessage {
    let role: String
    let text: String
    let action: String
    let characterID: String?
    let expressionID: String?
    let knowledgeCards: [KnowledgeCard]
}

struct SessionCloseSummary {
    let journalSummary: String
    let memoryCount: Int
    let stateProfileCount: Int
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

final class ChatService {
    private let baseURL: URL
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
            let knowledgeCards = response.knowledgeCards.map(\.knowledgeCard)
            let groupMessages = response.groupMessages ?? []
            let cardTargetIndex = groupMessages.firstIndex {
                $0.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "main"
            } ?? max(0, groupMessages.count - 1)
            return ChatServiceResponse(
                sessionID: sessionID,
                reply: response.reply,
                characterID: response.character?.id ?? character.id,
                expressionID: response.expression?.id ?? response.routePlan?.expressionID,
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
                routeSummary: Self.routeSummary(response.routePlan),
                usedFallback: false,
                notice: nil,
                backendURL: backendURLDescription,
                errorDetail: nil
            )
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

    func closeCurrentSession() async throws -> SessionCloseSummary {
        guard let sessionID else {
            throw ChatServiceError.noActiveSession
        }
        let request = try makeJSONRequest(path: "/api/end", body: EndSessionRequestBody(sessionID: sessionID))
        let response: EndSessionResponseBody = try await decode(request)
        self.sessionID = nil
        return SessionCloseSummary(
            journalSummary: response.journal.summary,
            memoryCount: response.memories.count,
            stateProfileCount: response.stateProfiles.count
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
        request.timeoutInterval = 20
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
            // 真机用公网隧道
            return URL(string: "https://g4c5324a.natappfree.cc")!
            // 真机用局域网 IP
            // return URL(string: "http://192.168.2.124:8765")!
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
            knowledgeCardIDs: knowledgeCardIDs ?? []
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

    var starMapInsight: StarMapInsight {
        StarMapInsight(
            id: id,
            generatedAt: Self.date(from: generatedAt) ?? Date(),
            periodStart: Self.date(from: periodStart) ?? Date(),
            periodEnd: Self.date(from: periodEnd) ?? Date(),
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
}

private struct EndSessionMemoryBody: Decodable {}

private struct EndSessionStateProfileBody: Decodable {}

private enum ChatServiceError: Error, CustomStringConvertible {
    case invalidResponse
    case httpStatus(Int)
    case noActiveSession

    var description: String {
        switch self {
        case .invalidResponse:
            return "后端响应格式无效"
        case .httpStatus(let status):
            return "HTTP \(status)"
        case .noActiveSession:
            return "还没有正在进行的会话"
        }
    }
}
