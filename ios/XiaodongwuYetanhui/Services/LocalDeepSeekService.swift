import Foundation

struct LocalChatResult {
    let sessionID: String
    let userMessage: ChatMessage
    let assistantMessages: [ChatMessage]
}

struct LocalJournalDraft: Decodable {
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
}

struct LocalMemoryDraft: Decodable {
    let category: String
    let subcategory: String
    let keywords: [String]
    let content: String
    let evidence: String
    let confidence: Double
    let importance: Int
}

struct LocalStateProfileDraft: Decodable {
    let action: String?
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String

    enum CodingKeys: String, CodingKey {
        case action
        case domain
        case stage
        case summary
        case intensity
        case trend
        case confidence
        case evidence
        case supportStrategy = "support_strategy"
    }
}

private struct LocalRoutePlan: Codable {
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

    var metadata: [String: Any] {
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

    var summary: String {
        let character = CompanionFixtures.character(id: characterID)
        let name = character?.name ?? "森森兔"
        let expression = character?.expression(id: expressionID)?.label ?? expressionID
        return "本轮规划 · \(responseMode)：\(name) · \(expression)；\(reason)"
    }
}

private struct LocalReplyDraft: Decodable {
    let reply: String
    let expressionID: String?

    enum CodingKeys: String, CodingKey {
        case reply
        case expressionID = "expression_id"
    }
}

private struct LocalKnowledgeItem {
    let card: KnowledgeCard
    let keywords: [String]
}

final class LocalDeepSeekService {
    private let session: URLSession
    private var sessionID: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resetSession() {
        sessionID = nil
    }

    func useSession(_ sessionID: String) {
        self.sessionID = sessionID
    }

    func closeCurrentSession(apiKey: String, database: SQLiteDatabase) async throws -> SessionCloseSummary {
        guard let sessionID else {
            throw LocalDeepSeekError.noActiveSession
        }
        let messages = database.messages(sessionID: sessionID, limit: 120)
        guard !messages.isEmpty else {
            database.endLocalSession(sessionID)
            self.sessionID = nil
            return SessionCloseSummary(
                journalSummary: "这次会话没有需要整理的内容。",
                memoryCount: 0,
                stateProfileCount: 0
            )
        }
        let extraction = try await requestSessionExtraction(
            apiKey: apiKey,
            messages: messages,
            currentProfiles: database.stateProfiles(limit: 8)
        )
        database.addLocalJournal(sessionID: sessionID, journal: extraction.journal)
        database.addLocalMemories(sessionID: sessionID, memories: extraction.memories)
        database.upsertLocalStateProfiles(sessionID: sessionID, profiles: extraction.stateProfiles)
        database.endLocalSession(sessionID)
        self.sessionID = nil
        return SessionCloseSummary(
            journalSummary: extraction.journal.summary,
            memoryCount: extraction.memories.count,
            stateProfileCount: extraction.stateProfiles.filter { $0.action != "no_change" }.count
        )
    }

    func send(
        text: String,
        character: CompanionCharacter,
        apiKey: String,
        database: SQLiteDatabase
    ) async throws -> LocalChatResult {
        let activeSessionID: String
        if let sessionID {
            activeSessionID = sessionID
        } else {
            activeSessionID = database.createLocalSession()
            sessionID = activeSessionID
        }

        let userMessage = database.addLocalMessage(
            sessionID: activeSessionID,
            role: .user,
            content: text
        )
        let history = database.messages(sessionID: activeSessionID, limit: 24)
        let profiles = database.stateProfiles(limit: 8)
        let plan = try await requestPlan(
            apiKey: apiKey,
            history: history,
            profiles: profiles,
            fallbackCharacter: character
        )
        let selectedCharacter = CompanionFixtures.character(id: plan.characterID) ?? character
        let memories = database.contextMemories(
            queryTerms: plan.memoryQueries,
            limit: 8
        )
        let knowledgeCards = Self.retrieveKnowledgeCards(
            queryTerms: plan.knowledgeNeeds + plan.knowledgeQueries,
            limit: 3
        )
        let reply = try await requestReply(
            apiKey: apiKey,
            character: selectedCharacter,
            history: history,
            memories: memories,
            profiles: profiles,
            knowledgeCards: knowledgeCards,
            plan: plan
        )
        let expressionID = selectedCharacter.expression(id: reply.expressionID ?? plan.expressionID)?.id
            ?? selectedCharacter.defaultExpressionID
        let assistantMessage = database.addLocalMessage(
            sessionID: activeSessionID,
            role: .assistant,
            content: reply.reply,
            characterID: selectedCharacter.id,
            expressionID: expressionID,
            model: "deepseek-chat",
            routePlan: plan.metadata,
            knowledgeCards: knowledgeCards
        )
        return LocalChatResult(
            sessionID: activeSessionID,
            userMessage: userMessage,
            assistantMessages: [ChatMessage(
                id: assistantMessage.id,
                role: assistantMessage.role,
                content: assistantMessage.content,
                characterID: assistantMessage.characterID,
                createdAt: assistantMessage.createdAt,
                groupRole: assistantMessage.groupRole,
                action: assistantMessage.action,
                expressionID: assistantMessage.expressionID,
                routeSummary: plan.summary,
                knowledgeCards: knowledgeCards
            )]
        )
    }

    private func requestPlan(
        apiKey: String,
        history: [ChatMessage],
        profiles: [StateProfile],
        fallbackCharacter: CompanionCharacter
    ) async throws -> LocalRoutePlan {
        let historyText = history.suffix(12).map {
            "\($0.role == .user ? "用户" : "陪伴者")：\($0.content)"
        }.joined(separator: "\n")
        let profileText = profiles.map {
            "- [\($0.domain)] \($0.stage)：\($0.summary)；趋势 \($0.trend)，强度 \($0.intensity)/10"
        }.joined(separator: "\n")
        let characterText = CompanionFixtures.characters.map { character in
            let expressions = character.expressions.map { "\($0.id)=\($0.label)" }.joined(separator: "、")
            return "- \(character.id)：\(character.name)，\(character.tagline)；表情：\(expressions)"
        }.joined(separator: "\n")
        let prompt = """
        你是“森森物语”的本轮策略规划器，不直接回复用户。
        请结合当前对话和全部长期状态，规划用户状态、核心需要、风险、回复方式、兔子形态、表情和检索词。
        只输出 JSON，不要诊断，不要输出解释性正文。

        可用兔子形态：
        \(characterText)

        当前对话：
        \(historyText)

        长期状态：
        \(profileText.isEmpty ? "暂无" : profileText)

        JSON 字段：
        user_state, core_need, risk_level(low|medium|high),
        response_mode(stabilize|validate|insight|boundary|action|mixed),
        character_id(yoyo|momo|yoran), expression_id,
        knowledge_needs(0-5项), memory_queries(0-6项), knowledge_queries(0-6项),
        response_guidance, reason。
        默认形态可参考 \(fallbackCharacter.id)，但应根据本轮真实需要重新选择。
        """
        return try await requestJSON(
            apiKey: apiKey,
            messages: [DeepSeekMessage(role: "system", content: prompt)],
            maxTokens: 900,
            thinking: true
        )
    }

    private func requestReply(
        apiKey: String,
        character: CompanionCharacter,
        history: [ChatMessage],
        memories: [MemoryEntry],
        profiles: [StateProfile],
        knowledgeCards: [KnowledgeCard],
        plan: LocalRoutePlan
    ) async throws -> LocalReplyDraft {
        let prompt = systemPrompt(
            character: character,
            memories: memories,
            profiles: profiles,
            knowledgeCards: knowledgeCards,
            plan: plan
        )
        return try await requestJSON(
            apiKey: apiKey,
            messages: [DeepSeekMessage(role: "system", content: prompt)] + history.map {
                DeepSeekMessage(
                    role: $0.role == .user ? "user" : "assistant",
                    content: $0.content
                )
            },
            maxTokens: 1400,
            thinking: false
        )
    }

    private func requestSessionExtraction(
        apiKey: String,
        messages: [ChatMessage],
        currentProfiles: [StateProfile]
    ) async throws -> LocalSessionExtraction {
        let transcript = messages.map {
            "\($0.role == .user ? "用户" : "陪伴者")：\($0.content)"
        }.joined(separator: "\n")
        let profileText = currentProfiles.map {
            "- [\($0.domain)] \($0.stage)：\($0.summary)；证据：\($0.evidence)"
        }.joined(separator: "\n")
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekRequest(
                model: "deepseek-chat",
                messages: [
                    DeepSeekMessage(
                        role: "system",
                        content: """
                        你负责把一次中文心理陪伴对话整理为结构化数据。不要诊断，不要夸大，不要凭空补充事实。
                        只输出 JSON 对象，包含 journal、memories、state_profiles。
                        memories 只保留未来确实有帮助的稳定事实、偏好、关系模式或重要经历，0-5 条。
                        state_profiles 必须审阅六个 domain：self_relation、emotion_regulation、relationship、agency_boundary、trauma_pattern、meaning_value。
                        每个 domain 输出一次；证据不足使用 action=no_change，不要为了填满而猜测。
                        action=create|update 时，summary 必须整合仍然成立的旧画像与本次新证据，不能只写本次增量。
                        mood_score 使用 -5 到 5；confidence 使用 0 到 1；importance 使用 1 到 5。
                        """
                    ),
                    DeepSeekMessage(
                        role: "user",
                        content: """
                        对话：
                        \(transcript)

                        当前已有长期画像：
                        \(profileText.isEmpty ? "暂无" : profileText)

                        JSON 格式：
                        {
                          "journal": {
                            "summary": "",
                            "emotion_curve": [],
                            "keywords": [],
                            "insights": [],
                            "suggested_next_step": "",
                            "mood_score": 0,
                            "dominant_emotion": ""
                          },
                          "memories": [{
                            "category": "",
                            "subcategory": "general",
                            "keywords": [],
                            "content": "",
                            "evidence": "",
                            "confidence": 0.7,
                            "importance": 3
                          }],
                          "state_profiles": [{
                            "action": "create | update | no_change",
                            "domain": "",
                            "stage": "",
                            "summary": "",
                            "intensity": 5,
                            "trend": "stable",
                            "confidence": 0.7,
                            "evidence": [],
                            "support_strategy": ""
                          }]
                        }
                        """
                    ),
                ],
                temperature: 0.2,
                maxTokens: 2200,
                stream: false,
                responseFormat: DeepSeekResponseFormat(type: "json_object")
            )
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalDeepSeekError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw LocalDeepSeekError.httpStatus(httpResponse.statusCode, detail)
        }
        let payload = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let content = payload.choices.first?.message.content,
              let contentData = content.data(using: .utf8)
        else {
            throw LocalDeepSeekError.invalidResponse
        }
        return try JSONDecoder().decode(LocalSessionExtraction.self, from: contentData)
    }

    private func systemPrompt(
        character: CompanionCharacter,
        memories: [MemoryEntry],
        profiles: [StateProfile],
        knowledgeCards: [KnowledgeCard],
        plan: LocalRoutePlan
    ) -> String {
        let memoryText = memories.map { "- \($0.content)" }.joined(separator: "\n")
        let profileText = profiles.map { "- \($0.domain)：\($0.summary)" }.joined(separator: "\n")
        let knowledgeText = knowledgeCards.map { "- \($0.title)：\($0.concept)" }.joined(separator: "\n")
        return """
        你是森森物语里的\(character.name)，是一位温和、清醒、有边界的自我理解型心理陪伴者，不是治疗师，也不做诊断。

        回应要求：
        - 优先复述和澄清用户的感受，不急着解释。
        - 每次最多引入一个心理学视角。
        - 给出一个很小、现实、低压力的下一步。
        - 不制造依赖，不强行积极。
        - 如出现明确自伤、他伤或现实危险，优先建议联系当地紧急服务和可信任的现实支持。
        - 使用中文，通常 3-7 段。
        - 只输出 JSON：{"reply":"回复正文","expression_id":"当前形态可用表情 id"}。

        当前角色气质：\(character.tagline)。\(character.voice)

        本轮规划：
        - 用户状态：\(plan.userState)
        - 核心需要：\(plan.coreNeed)
        - 风险等级：\(plan.riskLevel)
        - 回复模式：\(plan.responseMode)
        - 写作提醒：\(plan.responseGuidance)

        手机本地保存的长期记忆：
        \(memoryText.isEmpty ? "暂无" : memoryText)

        手机本地保存的长期状态：
        \(profileText.isEmpty ? "暂无" : profileText)

        本轮检索到的心理知识卡：
        \(knowledgeText.isEmpty ? "暂无；不要为了展示知识而强行解释。" : knowledgeText)
        """
    }

    private func requestJSON<Response: Decodable>(
        apiKey: String,
        messages: [DeepSeekMessage],
        maxTokens: Int,
        thinking: Bool
    ) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = thinking ? 120 : 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekRequest(
                model: "deepseek-chat",
                messages: messages,
                temperature: thinking ? nil : 0.7,
                maxTokens: maxTokens,
                stream: false,
                responseFormat: DeepSeekResponseFormat(type: "json_object"),
                thinking: DeepSeekThinking(type: thinking ? "enabled" : "disabled"),
                reasoningEffort: thinking ? "high" : nil
            )
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalDeepSeekError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw LocalDeepSeekError.httpStatus(httpResponse.statusCode, detail)
        }
        let payload = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard
            let content = payload.choices.first?.message.content,
            let contentData = content.data(using: .utf8)
        else {
            throw LocalDeepSeekError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: contentData)
    }

    private static func retrieveKnowledgeCards(queryTerms: [String], limit: Int) -> [KnowledgeCard] {
        let normalizedTerms = queryTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !normalizedTerms.isEmpty else { return [] }
        return localKnowledgeLibrary
            .map { item in
                let text = ([item.card.title, item.card.concept] + item.keywords)
                    .joined(separator: " ")
                    .lowercased()
                let score = normalizedTerms.reduce(0) { partial, term in
                    partial + (text.contains(term) ? 3 : item.keywords.filter { term.contains($0.lowercased()) }.count)
                }
                return (item.card, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private static let localKnowledgeLibrary: [LocalKnowledgeItem] = [
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "inner-critic", title: "严苛的内在批判者", concept: "长期自责可能曾经是一种求生和维持控制感的策略，但会在后来变成持续的自我攻击。"),
            keywords: ["自责", "内在批判", "完美主义", "道德化", "羞耻"]
        ),
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "emotional-flashback", title: "情绪闪回", concept: "当下的强烈羞耻、恐惧或无助，有时连接着过去未被消化的关系经验。"),
            keywords: ["情绪闪回", "创伤", "恐惧", "羞耻", "无助"]
        ),
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "freeze-response", title: "冻结与耗竭", concept: "长期压力下的无法启动不一定是意志薄弱，也可能是神经系统在降低消耗、保护自己。"),
            keywords: ["冻结", "耗竭", "疲惫", "无法启动", "神经系统"]
        ),
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "self-compassion", title: "自我同情", concept: "自我同情不是放弃要求，而是在困难中用对待重要他人的方式对待自己。"),
            keywords: ["自我同情", "自我接纳", "苛责", "善待自己"]
        ),
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "boundary", title: "边界与主体性", concept: "边界不是控制别人，而是辨认自己愿意承担什么，并为自己的选择和退出负责。"),
            keywords: ["边界", "主体性", "拒绝", "关系", "控制"]
        ),
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "control-illusion", title: "全能控制感", concept: "人在长期无力中可能把不可控的问题压缩成“只要我足够好就能解决”，从而获得短期希望。"),
            keywords: ["控制感", "全能控制", "向内归因", "完美", "家庭"]
        ),
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "cognitive-fusion", title: "想法不等于事实", concept: "痛苦的念头可以被看见和命名，但念头本身并不自动构成事实、命令或道德结论。"),
            keywords: ["念头", "事实", "认知融合", "道德审判", "焦虑"]
        ),
        LocalKnowledgeItem(
            card: KnowledgeCard(id: "distress-tolerance", title: "痛苦耐受", concept: "高强度时刻可以先降低刺激、锚定身体和延迟重大决定，再处理复杂问题。"),
            keywords: ["痛苦耐受", "稳定", "锚定", "危机", "高强度"]
        ),
    ]
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [DeepSeekMessage]
    let temperature: Double?
    let maxTokens: Int
    let stream: Bool
    var responseFormat: DeepSeekResponseFormat? = nil
    var thinking: DeepSeekThinking? = nil
    var reasoningEffort: String? = nil

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case responseFormat = "response_format"
        case thinking
        case reasoningEffort = "reasoning_effort"
    }
}

private struct DeepSeekResponseFormat: Encodable {
    let type: String
}

private struct DeepSeekThinking: Encodable {
    let type: String
}

private struct DeepSeekMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekResponse: Decodable {
    let choices: [DeepSeekChoice]
}

private struct DeepSeekChoice: Decodable {
    let message: DeepSeekMessage
}

private struct LocalSessionExtraction: Decodable {
    let journal: LocalJournalDraft
    let memories: [LocalMemoryDraft]
    let stateProfiles: [LocalStateProfileDraft]

    enum CodingKeys: String, CodingKey {
        case journal
        case memories
        case stateProfiles = "state_profiles"
    }
}

enum LocalDeepSeekError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "DeepSeek 返回了无法识别的响应"
        case .httpStatus(let status, let detail):
            return "DeepSeek API 请求失败（HTTP \(status)）\(detail.isEmpty ? "" : "：\(detail)")"
        case .noActiveSession:
            return "还没有正在进行的本地会话"
        }
    }
}
