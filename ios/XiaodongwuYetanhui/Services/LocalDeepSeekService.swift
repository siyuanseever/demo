import Foundation

// MARK: - 与 Python 后端 parse_json_object 完全一致的 JSON 容错解析

/// 等价于 Python 后端的 `parse_json_object(content)`：
/// 1. 先尝试 json.loads 整段文本
/// 2. 失败则提取第一个 { 到最后一个 } 的子串再解析
/// 3. 都失败返回 nil
private func parseJSONObject(_ content: String) -> [String: Any]? {
    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    // 先尝试直接解析
    if let data = text.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data, options: []),
       let dict = obj as? [String: Any] {
        return dict
    }

    // 失败则提取第一个 { 到最后一个 } 再解析（和 Python 后端 parse_json_object 一致）
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}"),
          start < end else { return nil }

    let substring = String(text[start...end])
    if let data = substring.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers, .fragmentsAllowed]),
       let dict = obj as? [String: Any] {
        return dict
    }

    return nil
}

/// 从 parseJSONObject 的结果中安全提取值
private func stringFromDict(_ dict: [String: Any], _ key: String) -> String {
    (dict[key] as? String) ?? ""
}

private func stringArrayFromDict(_ dict: [String: Any], _ key: String) -> [String] {
    guard let arr = dict[key] as? [Any] else { return [] }
    return arr.compactMap { $0 as? String }
}

private func intFromDict(_ dict: [String: Any], _ key: String) -> Int {
    (dict[key] as? Int) ?? 0
}

private func doubleFromDict(_ dict: [String: Any], _ key: String) -> Double {
    (dict[key] as? Double) ?? 0.0
}

private func dictFromDict(_ dict: [String: Any], _ key: String) -> [String: Any] {
    (dict[key] as? [String: Any]) ?? [:]
}

private func dictArrayFromDict(_ dict: [String: Any], _ key: String) -> [[String: Any]] {
    guard let arr = dict[key] as? [Any] else { return [] }
    return arr.compactMap { $0 as? [String: Any] }
}

struct LocalChatResult {
    let sessionID: String
    let userMessage: ChatMessage
    let quickReply: ChatMessage?
    let followUpReply: ChatMessage?
    let nextAction: String
}

struct LocalJournalDraft {
    let summary: String
    let emotionCurve: [String]
    let keywords: [String]
    let insights: [String]
    let suggestedNextStep: String
    let moodScore: Int
    let dominantEmotion: String
}

struct LocalMemoryDraft {
    let category: String
    let subcategory: String
    let keywords: [String]
    let content: String
    let evidence: String
    let confidence: Double
    let importance: Int
}

struct LocalStateProfileDraft {
    let action: String?
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String
}

private struct LocalRoutePlan {
    let nextAction: String
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
    let actionReply: String

    var metadata: [String: Any] {
        [
            "next_action": nextAction,
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
            "action_reply": actionReply,
        ]
    }

    var summary: String {
        let character = CompanionFixtures.character(id: characterID)
        let name = character?.name ?? "森森兔"
        let expression = character?.expression(id: expressionID)?.label ?? expressionID
        return "本轮规划 · \(nextAction) · \(responseMode)：\(name) · \(expression)；\(reason)"
    }
}

private struct LocalReplyDraft {
    let reply: String
    let expressionID: String?
}

private struct LocalKnowledgeItem {
    let card: KnowledgeCard
    let keywords: [String]
}

final class LocalDeepSeekService {
    private let session: URLSession
    private var sessionID: String?
    var currentSessionID: String? { sessionID }

    func clearSession() {
        sessionID = nil
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resetSession() {
        sessionID = nil
    }

    func testConnection(apiKey: String) async throws -> Bool {
        fputs("[DeepSeek Test] 开始测试连接...\n", stderr)
        let requestBody = DeepSeekRequest(
            model: "deepseek-chat",
            messages: [
                DeepSeekMessage(role: "user", content: "ping")
            ],
            temperature: 0.7,
            maxTokens: 10,
            stream: false,
            responseFormat: nil,
            thinking: DeepSeekThinking(type: "disabled"),
            reasoningEffort: nil
        )
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            fputs("[DeepSeek Test] 请求体编码成功，大小: \(request.httpBody?.count ?? 0) bytes\n", stderr)
        } catch {
            fputs("[DeepSeek Test] 请求体编码失败: \(error)\n", stderr)
            throw error
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                fputs("[DeepSeek Test] 无效响应类型\n", stderr)
                throw LocalDeepSeekError.invalidResponse
            }
            fputs("[DeepSeek Test] HTTP 状态码: \(httpResponse.statusCode)\n", stderr)
            guard (200..<300).contains(httpResponse.statusCode) else {
                let detail = String(data: data, encoding: .utf8) ?? ""
                fputs("[DeepSeek Test] HTTP 错误: \(detail)\n", stderr)
                throw LocalDeepSeekError.httpStatus(httpResponse.statusCode, detail)
            }
            fputs("[DeepSeek Test] 连接测试成功!\n", stderr)
            return true
        } catch {
            fputs("[DeepSeek Test] 请求失败: \(error.localizedDescription)\n", stderr)
            fputs("[DeepSeek Test] 错误详情: \(error)\n", stderr)
            throw error
        }
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

        let closeMemories = extraction.memories.map { memory in
            SessionCloseMemory(
                id: UUID().uuidString,
                category: memory.category,
                subcategory: memory.subcategory,
                content: memory.content,
                keywords: memory.keywords,
                action: "create",
                reason: memory.evidence,
                confidence: memory.confidence,
                importance: memory.importance
            )
        }

        let closeStateProfiles = extraction.stateProfiles.map { profile in
            SessionCloseStateProfile(
                domain: profile.domain,
                stage: profile.stage,
                summary: profile.summary,
                intensity: profile.intensity,
                trend: profile.trend,
                confidence: profile.confidence,
                evidence: profile.evidence,
                supportStrategy: profile.supportStrategy,
                action: profile.action ?? "no_change",
                reason: ""
            )
        }

        return SessionCloseSummary(
            journalSummary: extraction.journal.summary,
            memoryCount: extraction.memories.count,
            stateProfileCount: extraction.stateProfiles.filter { $0.action != "no_change" }.count,
            journal: SessionCloseJournal(
                summary: extraction.journal.summary,
                emotionCurve: extraction.journal.emotionCurve,
                keywords: extraction.journal.keywords,
                insights: extraction.journal.insights,
                suggestedNextStep: extraction.journal.suggestedNextStep,
                moodScore: extraction.journal.moodScore,
                dominantEmotion: extraction.journal.dominantEmotion
            ),
            memories: closeMemories,
            stateProfiles: closeStateProfiles
        )
    }

    @MainActor
    func send(
        text: String,
        character: CompanionCharacter,
        apiKey: String,
        database: SQLiteDatabase,
        onQuickReply: (@MainActor (ChatMessage) -> Void)? = nil
    ) async throws -> LocalChatResult {
        fputs("[LocalDeepSeek] send 开始，text: \(text)\n", stderr)
        let activeSessionID: String
        if let sessionID {
            activeSessionID = sessionID
            fputs("[LocalDeepSeek] 复用已有 session: \(activeSessionID)\n", stderr)
        } else {
            activeSessionID = database.createLocalSession()
            sessionID = activeSessionID
            fputs("[LocalDeepSeek] 创建新 session: \(activeSessionID)\n", stderr)
        }

        let userMessage = database.addLocalMessage(
            sessionID: activeSessionID,
            role: .user,
            content: text
        )
        fputs("[LocalDeepSeek] 用户消息已保存\n", stderr)
        let history = database.messages(sessionID: activeSessionID, limit: 24)
        let profiles = database.stateProfiles(limit: 8)
        fputs("[LocalDeepSeek] 历史消息数: \(history.count), 状态画像数: \(profiles.count)\n", stderr)
        
        fputs("[LocalDeepSeek] 并行启动 requestQuickReply + requestPlan\n", stderr)
        let parallelStartedAt = Date()
        async let planOperation = requestPlan(
            apiKey: apiKey,
            history: history,
            profiles: profiles,
            fallbackCharacter: character
        )
        async let quickOperation = requestQuickReply(
            apiKey: apiKey,
            character: character,
            history: history
        )

        let quickReply: LocalReplyDraft?
        do {
            quickReply = try await quickOperation
            if let qr = quickReply {
                let elapsed = Date().timeIntervalSince(parallelStartedAt)
                fputs("[LocalDeepSeek] requestQuickReply 成功, elapsed: \(String(format: "%.2f", elapsed))s, 回复长度: \(qr.reply.count)\n", stderr)
            }
        } catch {
            fputs("[LocalDeepSeek] requestQuickReply 失败: \(error)\n", stderr)
            quickReply = nil
        }

        let quickExpressionID = character.expression(id: quickReply?.expressionID ?? character.defaultExpressionID)?.id
            ?? character.defaultExpressionID
        var quickMessage: ChatMessage? = nil
        if let qr = quickReply {
            let qm = database.addLocalMessage(
                sessionID: activeSessionID,
                role: .assistant,
                content: qr.reply,
                characterID: character.id,
                expressionID: quickExpressionID,
                model: "deepseek-chat",
                routePlan: ["next_action": "pending_plan"],
                knowledgeCards: []
            )
            quickMessage = ChatMessage(
                id: qm.id,
                role: qm.role,
                content: qm.content,
                characterID: qm.characterID,
                createdAt: qm.createdAt,
                groupRole: qm.groupRole,
                action: qm.action,
                expressionID: qm.expressionID,
                routeSummary: nil,
                knowledgeCards: []
            )
            fputs("[LocalDeepSeek] 快速回复消息已保存\n", stderr)
            if let callback = onQuickReply, let qm = quickMessage {
                callback(qm)
                fputs("[LocalDeepSeek] 快速回复回调已触发\n", stderr)
            }
        }

        let plan: LocalRoutePlan
        do {
            plan = try await planOperation
            let elapsed = Date().timeIntervalSince(parallelStartedAt)
            fputs("[LocalDeepSeek] requestPlan 成功, elapsed: \(String(format: "%.2f", elapsed))s, next_action: \(plan.nextAction), character_id: \(plan.characterID)\n", stderr)
        } catch {
            fputs("[LocalDeepSeek] requestPlan 失败: \(error)\n", stderr)
            if quickMessage != nil {
                return LocalChatResult(
                    sessionID: activeSessionID,
                    userMessage: userMessage,
                    quickReply: quickMessage,
                    followUpReply: nil,
                    nextAction: "quick_only_plan_failed"
                )
            }
            throw error
        }

        let selectedCharacter = CompanionFixtures.character(id: plan.characterID) ?? character
        let normalizedAction = normalizeNextAction(plan.nextAction)
        if normalizedAction == "quick_only", quickMessage != nil {
            fputs("[LocalDeepSeek] plan 决定 quick_only，本轮不再生成第二次回复\n", stderr)
            return LocalChatResult(
                sessionID: activeSessionID,
                userMessage: userMessage,
                quickReply: quickMessage,
                followUpReply: nil,
                nextAction: normalizedAction
            )
        }

        if ["clarify", "interaction"].contains(normalizedAction), quickMessage != nil {
            let actionText = plannedActionReply(plan: plan, character: selectedCharacter)
            let actionMessage = database.addLocalMessage(
                sessionID: activeSessionID,
                role: .assistant,
                content: actionText,
                characterID: selectedCharacter.id,
                expressionID: plan.expressionID,
                model: "route-plan",
                routePlan: plan.metadata,
                knowledgeCards: []
            )
            return LocalChatResult(
                sessionID: activeSessionID,
                userMessage: userMessage,
                quickReply: quickMessage,
                followUpReply: ChatMessage(
                    id: actionMessage.id,
                    role: actionMessage.role,
                    content: actionMessage.content,
                    characterID: actionMessage.characterID,
                    createdAt: actionMessage.createdAt,
                    groupRole: actionMessage.groupRole,
                    action: normalizedAction,
                    expressionID: actionMessage.expressionID,
                    routeSummary: plan.summary,
                    knowledgeCards: []
                ),
                nextAction: normalizedAction
            )
        }

        let memories = database.contextMemories(
            queryTerms: plan.memoryQueries,
            limit: 8
        )
        let knowledgeCards = Self.retrieveKnowledgeCards(
            queryTerms: plan.knowledgeNeeds + plan.knowledgeQueries,
            limit: 3
        )

        fputs("[LocalDeepSeek] 开始 requestDeepReply...\n", stderr)
        let deepReply: LocalReplyDraft
        do {
            deepReply = try await requestDeepReply(
                apiKey: apiKey,
                character: selectedCharacter,
                history: history,
                memories: memories,
                profiles: profiles,
                knowledgeCards: knowledgeCards,
                plan: plan,
                quickReplyText: quickReply?.reply
            )
            fputs("[LocalDeepSeek] requestDeepReply 成功, 回复长度: \(deepReply.reply.count)\n", stderr)
        } catch {
            fputs("[LocalDeepSeek] requestDeepReply 失败: \(error)\n", stderr)
            if quickMessage != nil {
                return LocalChatResult(
                    sessionID: activeSessionID,
                    userMessage: userMessage,
                    quickReply: quickMessage,
                    followUpReply: nil,
                    nextAction: "quick_only_deep_failed"
                )
            }
            throw error
        }
        
        let deepExpressionID = selectedCharacter.expression(id: deepReply.expressionID ?? plan.expressionID)?.id
            ?? selectedCharacter.defaultExpressionID
        let assistantMessage = database.addLocalMessage(
            sessionID: activeSessionID,
            role: .assistant,
            content: deepReply.reply,
            characterID: selectedCharacter.id,
            expressionID: deepExpressionID,
            model: "deepseek-chat",
            routePlan: plan.metadata,
            knowledgeCards: knowledgeCards
        )
        fputs("[LocalDeepSeek] 深度回复消息已保存\n", stderr)
        return LocalChatResult(
            sessionID: activeSessionID,
            userMessage: userMessage,
            quickReply: quickMessage,
            followUpReply: ChatMessage(
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
            ),
            nextAction: "deep"
        )
    }

    private func normalizeNextAction(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["deep", "quick_only", "clarify", "interaction"].contains(normalized)
            ? normalized
            : "deep"
    }

    private func plannedActionReply(plan: LocalRoutePlan, character: CompanionCharacter) -> String {
        let provided = plan.actionReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provided.isEmpty {
            return provided
        }
        if normalizeNextAction(plan.nextAction) == "interaction" {
            return "\(character.name)想先陪你慢一点。我们一起做一次轻轻的呼吸：吸气、停一下，再慢慢呼出去。做完以后，你愿意告诉我身体有没有松开一点吗？"
        }
        return "\(character.name)想再确认一下：你此刻更需要的是有人理解这份感受，还是一起理清接下来可以怎么做？"
    }

    /// 发送一次 requestPlan API 请求，返回 content 文本
    private func requestPlanAPI(
        apiKey: String,
        prompt: String,
        maxTokens: Int,
        thinking: Bool
    ) async throws -> String {
        let request = try buildJSONRequest(
            apiKey: apiKey,
            messages: [DeepSeekMessage(role: "system", content: prompt)],
            maxTokens: maxTokens,
            thinking: thinking
        )
        let (data, _) = try await session.data(for: request)
        let payload = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let content = payload.choices.first?.message.content else {
            throw LocalDeepSeekError.invalidResponse
        }
        return content
    }

    private func requestPlan(
        apiKey: String,
        history: [ChatMessage],
        profiles: [StateProfile],
        fallbackCharacter: CompanionCharacter
    ) async throws -> LocalRoutePlan {
        let historyText = history.suffix(12).map { msg in
            let content = msg.content.count > 600 ? String(msg.content.prefix(600)) + "..." : msg.content
            return "\(msg.role == .user ? "用户" : "陪伴者")：\(content)"
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
        请结合当前对话和全部长期状态，规划用户状态、核心需要、风险、回复方式、兔子形态、表情、检索词，以及快速回应之后是否还需要第二步动作。
        只输出 JSON，不要诊断，不要输出解释性正文。

        可用兔子形态：
        \(characterText)

        当前对话：
        \(historyText)

        长期状态：
        \(profileText.isEmpty ? "暂无" : profileText)

        JSON 字段：
        next_action(deep|quick_only|clarify|interaction),
        user_state, core_need, risk_level(low|medium|high),
        response_mode(stabilize|validate|insight|boundary|action|mixed),
        character_id(yoyo|momo|yoran), expression_id,
        knowledge_needs(0-5项), memory_queries(0-6项), knowledge_queries(0-6项),
        response_guidance, reason, action_reply。
        规则：
        - deep：需要记忆/知识检索和更完整的第二次回复。
        - quick_only：简单问候、确认或 quick 已足够，不再追加回复。
        - clarify：信息不足，action_reply 直接给出一句温和澄清问题。
        - interaction：更适合一个简短练习，action_reply 直接给出低压力引导。
        默认形态可参考 \(fallbackCharacter.id)，但应根据本轮真实需要重新选择。
        """
        // 首次尝试：启用 thinking，给足够的 token 预算（thinking 和 content 共享 max_tokens）
        var content = try await requestPlanAPI(
            apiKey: apiKey,
            prompt: prompt,
            maxTokens: 4000,
            thinking: true
        )
        fputs("[LocalDeepSeek] requestPlan: content 长度: \(content.count)\n", stderr)

        // 如果 thinking 消耗了全部 token 导致 content 为空，用 thinking=false 重试
        if content.isEmpty {
            fputs("[LocalDeepSeek] requestPlan: content 为空（thinking 可能耗尽 token），用 thinking=false 重试\n", stderr)
            content = try await requestPlanAPI(
                apiKey: apiKey,
                prompt: prompt,
                maxTokens: 2200,
                thinking: false
            )
            fputs("[LocalDeepSeek] requestPlan 重试: content 长度: \(content.count)\n", stderr)
        }

        // 和 Python 后端 parse_json_object 一致的容错解析
        guard !content.isEmpty, let dict = parseJSONObject(content) else {
            fputs("[LocalDeepSeek] requestPlan: JSON 解析失败\n", stderr)
            throw LocalDeepSeekError.invalidResponse
        }
        fputs("[LocalDeepSeek] requestPlan: JSON 解析成功\n", stderr)
        return LocalRoutePlan(
            nextAction: stringFromDict(dict, "next_action").isEmpty ? "deep" : stringFromDict(dict, "next_action"),
            userState: stringFromDict(dict, "user_state"),
            coreNeed: stringFromDict(dict, "core_need"),
            riskLevel: stringFromDict(dict, "risk_level").isEmpty ? "low" : stringFromDict(dict, "risk_level"),
            responseMode: stringFromDict(dict, "response_mode").isEmpty ? "validate" : stringFromDict(dict, "response_mode"),
            characterID: stringFromDict(dict, "character_id").isEmpty ? fallbackCharacter.id : stringFromDict(dict, "character_id"),
            expressionID: stringFromDict(dict, "expression_id").isEmpty ? fallbackCharacter.defaultExpressionID : stringFromDict(dict, "expression_id"),
            knowledgeNeeds: stringArrayFromDict(dict, "knowledge_needs"),
            memoryQueries: stringArrayFromDict(dict, "memory_queries"),
            knowledgeQueries: stringArrayFromDict(dict, "knowledge_queries"),
            responseGuidance: stringFromDict(dict, "response_guidance"),
            reason: stringFromDict(dict, "reason"),
            actionReply: stringFromDict(dict, "action_reply")
        )
    }

    private func buildJSONRequest(
        apiKey: String,
        messages: [DeepSeekMessage],
        maxTokens: Int,
        thinking: Bool
    ) throws -> URLRequest {
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
        return request
    }

    private func requestQuickReply(
        apiKey: String,
        character: CompanionCharacter,
        history: [ChatMessage]
    ) async throws -> LocalReplyDraft {
        let prompt = """
        你是 \(character.name)，一位温柔、克制的心理陪伴者。你正在生成即时回应；后台会同时进行更完整的意图分析，所以不要等待分析结果。

        用户最后一句话：\(history.last?.content ?? "")

        请用 1-2 句话先接住用户，让用户明确感到消息已经被听见。不要深入分析，不要给复杂建议，也不要声称已经了解用户没有说出的内容。
        输出格式：JSON，包含 reply 和 expression_id 字段。
        """
        let request = try buildJSONRequest(
            apiKey: apiKey,
            messages: [DeepSeekMessage(role: "system", content: prompt)],
            maxTokens: 300,
            thinking: false
        )
        let (data, _) = try await session.data(for: request)
        let payload = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let content = payload.choices.first?.message.content else {
            throw LocalDeepSeekError.invalidResponse
        }
        fputs("[LocalDeepSeek] requestQuickReply: content 长度: \(content.count)\n", stderr)
        if let dict = parseJSONObject(content) {
            return LocalReplyDraft(
                reply: stringFromDict(dict, "reply"),
                expressionID: stringFromDict(dict, "expression_id").isEmpty ? character.defaultExpressionID : stringFromDict(dict, "expression_id")
            )
        }
        return LocalReplyDraft(
            reply: content.trimmingCharacters(in: .whitespacesAndNewlines),
            expressionID: character.defaultExpressionID
        )
    }

    private func requestDeepReply(
        apiKey: String,
        character: CompanionCharacter,
        history: [ChatMessage],
        memories: [MemoryEntry],
        profiles: [StateProfile],
        knowledgeCards: [KnowledgeCard],
        plan: LocalRoutePlan,
        quickReplyText: String? = nil
    ) async throws -> LocalReplyDraft {
        let prompt = systemPrompt(
            character: character,
            memories: memories,
            profiles: profiles,
            knowledgeCards: knowledgeCards,
            plan: plan,
            quickReplyText: quickReplyText
        )
        fputs("[LocalDeepSeek] requestDeepReply: 历史消息数: \(history.count)\n", stderr)
        let recentHistory = history.suffix(20).map { msg in
            let roleLabel = msg.role == .user ? "用户" : character.name
            let content = msg.content.count > 1200 ? String(msg.content.prefix(1200)) + "…" : msg.content
            return "\(roleLabel)：\(content)"
        }.joined(separator: "\n")
        let promptWithHistory = prompt + "\n\n当前对话历史：\n\(recentHistory)\n"
        let lastUserText = history.last?.content ?? ""
        let request = try buildJSONRequest(
            apiKey: apiKey,
            messages: [
                DeepSeekMessage(role: "system", content: promptWithHistory),
                DeepSeekMessage(role: "user", content: lastUserText)
            ],
            maxTokens: 2400,
            thinking: false
        )
        let (data, _) = try await session.data(for: request)
        let payload = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let content = payload.choices.first?.message.content else {
            throw LocalDeepSeekError.invalidResponse
        }
        fputs("[LocalDeepSeek] requestDeepReply: content 长度: \(content.count)\n", stderr)
        if let dict = parseJSONObject(content) {
            fputs("[LocalDeepSeek] requestDeepReply: JSON 解析成功\n", stderr)
            return LocalReplyDraft(
                reply: stringFromDict(dict, "reply"),
                expressionID: stringFromDict(dict, "expression_id").isEmpty ? plan.expressionID : stringFromDict(dict, "expression_id")
            )
        }
        fputs("[LocalDeepSeek] requestDeepReply: JSON 解析失败，使用原始文本\n", stderr)
        return LocalReplyDraft(
            reply: content.trimmingCharacters(in: .whitespacesAndNewlines),
            expressionID: plan.expressionID
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
        let request = try buildJSONRequest(
            apiKey: apiKey,
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
            maxTokens: 2200,
            thinking: false
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
        fputs("[LocalDeepSeek] requestSessionExtraction: content 长度: \(content.count)\n", stderr)
        guard let root = parseJSONObject(content) else {
            fputs("[LocalDeepSeek] requestSessionExtraction: JSON 解析失败\n", stderr)
            throw LocalDeepSeekError.invalidResponse
        }
        fputs("[LocalDeepSeek] requestSessionExtraction: JSON 解析成功\n", stderr)

        // 解析 journal
        let journalDict = dictFromDict(root, "journal")
        let journal = LocalJournalDraft(
            summary: stringFromDict(journalDict, "summary"),
            emotionCurve: stringArrayFromDict(journalDict, "emotion_curve"),
            keywords: stringArrayFromDict(journalDict, "keywords"),
            insights: stringArrayFromDict(journalDict, "insights"),
            suggestedNextStep: stringFromDict(journalDict, "suggested_next_step"),
            moodScore: intFromDict(journalDict, "mood_score"),
            dominantEmotion: stringFromDict(journalDict, "dominant_emotion")
        )

        // 解析 memories
        let memoryItems = dictArrayFromDict(root, "memories")
        let memories = memoryItems.compactMap { item -> LocalMemoryDraft? in
            let content = stringFromDict(item, "content")
            guard !content.isEmpty else { return nil }
            return LocalMemoryDraft(
                category: stringFromDict(item, "category"),
                subcategory: stringFromDict(item, "subcategory").isEmpty ? "general" : stringFromDict(item, "subcategory"),
                keywords: stringArrayFromDict(item, "keywords"),
                content: content,
                evidence: stringFromDict(item, "evidence"),
                confidence: doubleFromDict(item, "confidence") == 0 ? 0.7 : doubleFromDict(item, "confidence"),
                importance: intFromDict(item, "importance") == 0 ? 3 : intFromDict(item, "importance")
            )
        }

        // 解析 state_profiles
        let profileItems = dictArrayFromDict(root, "state_profiles")
        let stateProfiles = profileItems.compactMap { item -> LocalStateProfileDraft? in
            let domain = stringFromDict(item, "domain")
            guard !domain.isEmpty else { return nil }
            return LocalStateProfileDraft(
                action: stringFromDict(item, "action").isEmpty ? "no_change" : stringFromDict(item, "action"),
                domain: domain,
                stage: stringFromDict(item, "stage"),
                summary: stringFromDict(item, "summary"),
                intensity: intFromDict(item, "intensity") == 0 ? 5 : intFromDict(item, "intensity"),
                trend: stringFromDict(item, "trend").isEmpty ? "stable" : stringFromDict(item, "trend"),
                confidence: doubleFromDict(item, "confidence") == 0 ? 0.7 : doubleFromDict(item, "confidence"),
                evidence: stringArrayFromDict(item, "evidence"),
                supportStrategy: stringFromDict(item, "support_strategy")
            )
        }

        return LocalSessionExtraction(
            journal: journal,
            memories: memories,
            stateProfiles: stateProfiles
        )
    }

    private func systemPrompt(
        character: CompanionCharacter,
        memories: [MemoryEntry],
        profiles: [StateProfile],
        knowledgeCards: [KnowledgeCard],
        plan: LocalRoutePlan,
        quickReplyText: String? = nil
    ) -> String {
        let memoryText = memories.map { "- [\($0.category)/\($0.subcategory)] \($0.content)（关键词：\($0.keywords.joined(separator: "、"))）" }.joined(separator: "\n")
        let profileText = profiles.map { "- [\($0.domain)] 阶段：\($0.stage)；摘要：\($0.summary)；趋势：\($0.trend)；强度：\($0.intensity)/10" }.joined(separator: "\n")
        let knowledgeText = knowledgeCards.map { "- \($0.title)：\($0.concept)" }.joined(separator: "\n")
        let quickContext = quickReplyText.map { "\n你刚才已经快速回应了用户一句话：「\($0)」。现在请你在这个基础上展开更完整、更深入的回复。不要重复刚才已经说过的那句话，而是从那里继续往前推进一层。" } ?? ""
        return """
        你是森森物语里的\(character.name)，是一位温和、清醒、有边界的自我理解型心理陪伴者。

        你的职责不是给建议、不是安慰、不是讲道理。你的职责是：帮用户看清自己此刻正在经历什么。

        \(quickContext)

        回应要求：
        - 用你自己的话复述用户的感受和处境，让用户感到「你确实听懂了」。
        - 把你读到的长期记忆或状态画像里相关的内容，自然地编织进回应里。比如「我记得你之前提到过……」或「从最近的状态来看，你似乎在……」。这让用户感到被记住、被理解。
        - 如果记忆中有和当前话题直接相关的内容，一定要引用它。这是你最有价值的地方——你不是一个只会说套话的机器人，你真的记得用户说过什么。
        - 最多引入一个心理知识视角，但不要生硬地贴标签。用日常语言解释，让它感觉像是你在理解用户的过程中自然联想到的，而不是在给用户上课。
        - 结尾给一个很小、很具体、不费力的下一步。不是「你可以试试多休息」，而是更具体的——比如「如果今晚你发现自己又在反复想这件事，可以先停下来，喝一口水，告诉自己：这件事我明天再想。」
        - 不制造依赖，不强行积极，不给空洞的安慰。你的温度来自理解，不来自甜言蜜语。
        - 如果用户表现出自伤、他伤或现实危险，优先建议联系当地紧急服务和可信任的现实支持。
        - 使用中文，4-8 段。
        - 只输出 JSON：{"reply":"回复正文","expression_id":"表情 id"}。

        关于你——\(character.name)：
        \(character.tagline)
        \(character.voice)

        本轮分析：
        - 用户状态：\(plan.userState)
        - 核心需要：\(plan.coreNeed)
        - 风险等级：\(plan.riskLevel)
        - 回复模式：\(plan.responseMode)
        - 写作方向：\(plan.responseGuidance)

        用户过往的长期记忆（请注意：这些是你应该引用的素材）：
        \(memoryText.isEmpty ? "暂无" : memoryText)

        用户的长期状态画像：
        \(profileText.isEmpty ? "暂无" : profileText)

        可参考的心理知识视角：
        \(knowledgeText.isEmpty ? "暂无" : knowledgeText)
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
        fputs("[LocalDeepSeek] requestJSON: 响应数据大小: \(data.count) bytes\n", stderr)
        guard let httpResponse = response as? HTTPURLResponse else {
            fputs("[LocalDeepSeek] requestJSON: 无效响应类型\n", stderr)
            throw LocalDeepSeekError.invalidResponse
        }
        fputs("[LocalDeepSeek] requestJSON: HTTP 状态码: \(httpResponse.statusCode)\n", stderr)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            fputs("[LocalDeepSeek] requestJSON: HTTP 错误 \(httpResponse.statusCode): \(detail)\n", stderr)
            throw LocalDeepSeekError.httpStatus(httpResponse.statusCode, detail)
        }
        let responseStr = String(data: data, encoding: .utf8) ?? ""
        fputs("[LocalDeepSeek] requestJSON: 响应内容前500字符: \(String(responseStr.prefix(500)))\n", stderr)
        let payload: DeepSeekResponse
        do {
            payload = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        } catch {
            fputs("[LocalDeepSeek] requestJSON: 外层 JSON 解码失败: \(error)\n", stderr)
            fputs("[LocalDeepSeek] requestJSON: 原始响应: \(responseStr)\n", stderr)
            throw error
        }
        guard
            let content = payload.choices.first?.message.content,
            let contentData = content.data(using: .utf8)
        else {
            fputs("[LocalDeepSeek] requestJSON: 无效响应内容\n", stderr)
            throw LocalDeepSeekError.invalidResponse
        }
        fputs("[LocalDeepSeek] requestJSON: content 长度: \(content.count)\n", stderr)
        let result: Response
        do {
            result = try JSONDecoder().decode(Response.self, from: contentData)
        } catch {
            fputs("[LocalDeepSeek] requestJSON: 内层 JSON 解码失败: \(error)\n", stderr)
            fputs("[LocalDeepSeek] requestJSON: content: \(content)\n", stderr)
            throw error
        }
        return result
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

private struct LocalSessionExtraction {
    let journal: LocalJournalDraft
    let memories: [LocalMemoryDraft]
    let stateProfiles: [LocalStateProfileDraft]
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
