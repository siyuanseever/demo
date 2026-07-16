import Foundation

// MARK: - 与 Python 后端 parse_json_object 完全一致的 JSON 容错解析

/// 等价于 Python 后端的 `parse_json_object(content)`：
/// 1. 先尝试 json.loads 整段文本
/// 2. 失败则提取第一个 { 到最后一个 } 的子串再解析
/// 3. 都失败返回 nil
private func parseJSONObject(_ content: String) -> [String: Any]? {
    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if let data = text.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data, options: []),
       let dict = obj as? [String: Any] {
        return dict
    }

    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}"),
          start < end else { return nil }

    var substring = String(text[start...end])
    if let data = substring.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers, .fragmentsAllowed]),
       let dict = obj as? [String: Any] {
        return dict
    }

    substring = fixUnescapedQuotes(substring)
    if let data = substring.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers, .fragmentsAllowed]),
       let dict = obj as? [String: Any] {
        return dict
    }

    return nil
}

private func fixUnescapedQuotes(_ jsonString: String) -> String {
    var result = jsonString
    var inString = false
    var escaped = false
    var i = result.startIndex

    while i < result.endIndex {
        let char = result[i]
        if escaped {
            escaped = false
            i = result.index(after: i)
            continue
        }

        if char == "\\" {
            escaped = true
            i = result.index(after: i)
            continue
        }

        if char == "\"" {
            if inString {
                inString = false
            } else {
                inString = true
            }
            i = result.index(after: i)
            continue
        }

        if inString && char == "\"" {
            result.insert("\\", at: i)
            i = result.index(after: i)
        }

        i = result.index(after: i)
    }

    return result
}

private func findJSONLikeKey(
    _ key: String,
    in text: String,
    range: Range<String.Index>? = nil
) -> Range<String.Index>? {
    let searchRange = range ?? text.startIndex..<text.endIndex
    for marker in ["\"\(key)\"", "“\(key)”", "”\(key)”", "“\(key)\""] {
        if let match = text.range(of: marker, range: searchRange) {
            return match
        }
    }
    return nil
}

private func trimJSONLikeString(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let quoteCharacters: Set<Character> = ["\"", "“", "”"]

    if let first = result.first, quoteCharacters.contains(first) {
        result.removeFirst()
    }
    result = result.trimmingCharacters(in: .whitespacesAndNewlines)
    if let last = result.last, quoteCharacters.contains(last) {
        result.removeLast()
    }

    return result
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\r", with: "\r")
        .replacingOccurrences(of: "\\t", with: "\t")
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\\\", with: "\\")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func removingRepeatedQuickPrefix(_ reply: String, quickReply: String?) -> String {
    let candidate = reply.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        let quickReply,
        !quickReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return candidate
    }

    let quick = quickReply.trimmingCharacters(in: .whitespacesAndNewlines)
    guard candidate.hasPrefix(quick) else { return candidate }

    let remainderStart = candidate.index(candidate.startIndex, offsetBy: quick.count)
    if remainderStart < candidate.endIndex {
        let boundary = candidate[remainderStart]
        let allowedBoundary = boundary.isWhitespace
            || "，。！？；：、,.!?;:".contains(boundary)
        guard allowedBoundary else { return candidate }
    }

    let separators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "，。！？；：、,.!?;:"))
    return candidate[remainderStart...]
        .trimmingCharacters(in: separators)
}

/// 只针对 reply / character_id / expression_id 三个已知字段做保守恢复。
/// 模型偶尔会把 JSON 字符串的结束引号写成中文弯引号；此时不能把整个 JSON 外壳展示给用户。
private func parseReplyPayload(_ content: String) -> (reply: String, characterID: String?, expressionID: String?)? {
    if let dict = parseJSONObject(content) {
        let reply = stringFromDict(dict, "reply").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return nil }
        let characterID = stringFromDict(dict, "character_id").trimmingCharacters(in: .whitespacesAndNewlines)
        let expressionID = stringFromDict(dict, "expression_id").trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            reply,
            characterID.isEmpty ? nil : characterID,
            expressionID.isEmpty ? nil : expressionID
        )
    }

    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let replyKey = findJSONLikeKey("reply", in: text),
          let replyColon = text[replyKey.upperBound...].firstIndex(of: ":"),
          let expressionKey = findJSONLikeKey(
              "expression_id",
              in: text,
              range: text.index(after: replyColon)..<text.endIndex
          ),
          let separator = text[..<expressionKey.lowerBound].lastIndex(of: ",") else {
        return nil
    }

    let replyStart = text.index(after: replyColon)
    guard replyStart <= separator else { return nil }
    let reply = trimJSONLikeString(String(text[replyStart..<separator]))
    guard !reply.isEmpty else { return nil }

    var expressionID: String?
    if let expressionColon = text[expressionKey.upperBound...].firstIndex(of: ":") {
        let rawExpression = String(text[text.index(after: expressionColon)...])
        let trimmed = rawExpression.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: "\"“”{},"))
        )
        let safeExpression = String(trimmed.prefix { character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
        })
        expressionID = safeExpression.isEmpty ? nil : safeExpression
    }

    return (reply, nil, expressionID)
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

private func validExpressionID(_ expressionID: String?, for character: CompanionCharacter) -> String? {
    guard let expressionID else { return nil }
    return character.expressions.first(where: { $0.id == expressionID })?.id
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
    let assessment: UserConversationAssessment?
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
    let historyTurnsNeeded: Int
    let needStateProfiles: Bool
    let needMoreMemories: Bool
    let contextStrategy: String

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
            "history_turns_needed": historyTurnsNeeded,
            "need_state_profiles": needStateProfiles,
            "need_more_memories": needMoreMemories,
            "context_strategy": contextStrategy,
        ]
    }

    var summary: String {
        let character = CompanionFixtures.character(id: characterID)
        let name = character?.name ?? "森森兔"
        let expression = character?.expression(id: expressionID)?.label ?? expressionID
        return "本轮规划 · \(nextAction) · \(responseMode)：\(name) · \(expression)；\(reason)"
    }

    func presentationMetadata(characterID effectiveCharacterID: String, expressionID effectiveExpressionID: String) -> [String: Any] {
        var result = metadata
        if effectiveCharacterID != characterID {
            result["planned_character_id"] = characterID
        }
        result["character_id"] = effectiveCharacterID
        result["expression_id"] = effectiveExpressionID
        return result
    }

    func presentationSummary(character: CompanionCharacter, expressionID effectiveExpressionID: String) -> String {
        let expression = character.expression(id: effectiveExpressionID)?.label ?? effectiveExpressionID
        return "本轮规划 · \(nextAction) · \(responseMode)：\(character.name) · \(expression)；\(reason)"
    }

    var assessment: UserConversationAssessment {
        UserConversationAssessment(
            userState: userState,
            coreNeed: coreNeed,
            riskLevel: riskLevel,
            responseMode: responseMode,
            reason: reason,
            nextAction: nextAction
        )
    }
}

private struct LocalReplyDraft {
    let reply: String
    let characterID: String?
    let expressionID: String?
    let retrievedMemories: [MemoryEntry]
    let retrievedKnowledgeCards: [KnowledgeCard]
}

private struct LocalKnowledgeItem {
    let card: KnowledgeCard
    let keywords: [String]
}

final class LocalDeepSeekService {
    private let session: URLSession
    private let endpoint: URL
    private var sessionID: String?
    var currentSessionID: String? { sessionID }
    
    // MARK: - Prompt 文件加载
    private static func loadPrompt(_ name: String) -> String {
        func preprocess(_ content: String) -> String {
            content
                .replacingOccurrences(of: "{{", with: "{")
                .replacingOccurrences(of: "}}", with: "}")
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "md"),
           let content = try? String(contentsOf: url) {
            return preprocess(content)
        }
        
        let projectBasePath = FileManager.default.currentDirectoryPath
        let promptPath = URL(fileURLWithPath: projectBasePath)
            .appendingPathComponent("app")
            .appendingPathComponent("prompts")
            .appendingPathComponent("\(name).md")
        
        if let content = try? String(contentsOf: promptPath) {
            return preprocess(content)
        }
        
        let fallbackPath = URL(fileURLWithPath: projectBasePath)
            .deletingLastPathComponent()
            .appendingPathComponent("app")
            .appendingPathComponent("prompts")
            .appendingPathComponent("\(name).md")
        
        if let content = try? String(contentsOf: fallbackPath) {
            return preprocess(content)
        }
        
        fatalError("""
            [LocalDeepSeek] Could not load prompt \(name).md
            Searched paths:
            1. Bundle.main: \(Bundle.main.bundlePath)
            2. app/prompts/ under current directory: \(projectBasePath)/app/prompts/\(name).md
            3. Parent directory: \(URL(fileURLWithPath: projectBasePath).deletingLastPathComponent().path)/app/prompts/\(name).md
            Make sure prompt markdown files exist in app/prompts/ and are accessible at runtime.
            """)
    }
    
    private static let personaPrompt = loadPrompt("persona")
    private static let weeklyFlowInsightPrompt = loadPrompt("weekly_flow_insight")
    private static let routePlanPrompt = loadPrompt("route_plan")
    private static let quickReplyPrompt = loadPrompt("quick_reply")
    private static let sessionExtractionPrompt = loadPrompt("session_extraction")
    private static let rabbitResponseInstructionPrompt = loadPrompt("rabbit_response_instruction")
    private static let quickReplyHandoffPrompt = loadPrompt("quick_reply_handoff")

    func clearSession() {
        sessionID = nil
    }

    init(
        session: URLSession = .shared,
        endpoint: URL? = nil
    ) {
        self.session = session
        self.endpoint = endpoint ?? Self.defaultEndpoint
    }

    private static var defaultEndpoint: URL {
#if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["SENSEN_DEEPSEEK_ENDPOINT"],
           let overriddenEndpoint = URL(string: rawValue),
           ["http", "https"].contains(overriddenEndpoint.scheme?.lowercased() ?? "") {
            return overriddenEndpoint
        }
#endif
        return URL(string: "https://api.deepseek.com/chat/completions")!
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
        var request = URLRequest(url: endpoint)
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

    func generateWeeklyFlowInsight(
        apiKey: String,
        database: SQLiteDatabase
    ) async throws -> StarMapInsight {
        let memories = database.memories(limit: 30)
        let journals = database.journals(limit: 12)
        let profiles = database.stateProfiles(limit: 12)
        let source = """
        最近总结：
        \(journals.map { "- [\($0.dominantEmotion)] \($0.summary)；下一步：\($0.suggestedNextStep)" }.joined(separator: "\n"))

        长期记忆：
        \(memories.map { "- [\($0.category)/\($0.subcategory)] \($0.content)" }.joined(separator: "\n"))

        长期状态：
        \(profiles.map { "- [\($0.domain)] \($0.summary)；趋势：\($0.trend)；支持：\($0.supportStrategy)" }.joined(separator: "\n"))
        """
        let prompt = Self.weeklyFlowInsightPrompt + "\n\n\(source)"
        let request = try buildJSONRequest(
            apiKey: apiKey,
            messages: [DeepSeekMessage(role: "system", content: prompt)],
            maxTokens: 2200,
            thinking: false
        )
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let content = response.choices.first?.message.content,
              let payload = parseJSONObject(content) else {
            throw LocalDeepSeekError.invalidResponse
        }

        let now = Date()
        let periodStart = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        return StarMapInsight(
            id: UUID().uuidString,
            generatedAt: now,
            periodStart: periodStart,
            periodEnd: now,
            primaryGoalTitle: stringFromDict(payload, "primary_goal_title"),
            primaryGoalReason: stringFromDict(payload, "primary_goal_reason"),
            primaryGoalNextStep: stringFromDict(payload, "primary_goal_next_step"),
            primaryGoalChallenge: stringFromDict(payload, "primary_goal_challenge"),
            secondaryGoalTitle: stringFromDict(payload, "secondary_goal_title"),
            secondaryGoalReason: stringFromDict(payload, "secondary_goal_reason"),
            secondaryGoalNextStep: stringFromDict(payload, "secondary_goal_next_step"),
            secondaryGoalChallenge: stringFromDict(payload, "secondary_goal_challenge"),
            recentEmotionSummary: stringFromDict(payload, "recent_emotion_summary"),
            recentEmotionTags: stringArrayFromDict(payload, "recent_emotion_tags"),
            flowSupport: stringFromDict(payload, "flow_support"),
            memoryCues: stringArrayFromDict(payload, "memory_cues"),
            coreInsight: stringFromDict(payload, "core_insight"),
            coreInsightDetail: stringFromDict(payload, "core_insight_detail"),
            recentPatternTitle: stringFromDict(payload, "recent_pattern_title"),
            recentPatternItems: stringArrayFromDict(payload, "recent_pattern_items"),
            recentPatternDetail: stringFromDict(payload, "recent_pattern_detail"),
            flowConditionTitle: stringFromDict(payload, "flow_condition_title"),
            flowConditionItems: stringArrayFromDict(payload, "flow_condition_items"),
            flowConditionDetail: stringFromDict(payload, "flow_condition_detail"),
            gentleReminderTitle: stringFromDict(payload, "gentle_reminder_title"),
            gentleReminder: stringFromDict(payload, "gentle_reminder"),
            gentleReminderDetail: stringFromDict(payload, "gentle_reminder_detail"),
            sourceSummary: stringFromDict(payload, "source_summary")
        )
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
        fputs("[LocalDeepSeek] send 开始，字符数: \(text.count)\n", stderr)
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

        let quickCharacter = CompanionFixtures.character(id: quickReply?.characterID) ?? character
        let quickExpressionID = validExpressionID(quickReply?.expressionID, for: quickCharacter)
            ?? quickCharacter.defaultExpressionID
        var quickMessage: ChatMessage? = nil
        if let qr = quickReply {
            let qm = database.addLocalMessage(
                sessionID: activeSessionID,
                role: .assistant,
                content: qr.reply,
                characterID: quickCharacter.id,
                expressionID: quickExpressionID,
                model: "deepseek-chat",
                routePlan: ["next_action": "pending_plan"],
                replyStage: "quick",
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
                replyStage: "quick",
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
                    nextAction: "quick_only_plan_failed",
                    assessment: nil
                )
            }
            throw error
        }

        let plannedCharacter = CompanionFixtures.character(id: plan.characterID) ?? character
        let selectedCharacter = quickMessage.flatMap { CompanionFixtures.character(id: $0.characterID) }
            ?? plannedCharacter
        let selectedPlanExpressionID = validExpressionID(plan.expressionID, for: selectedCharacter)
            ?? quickMessage?.expressionID
            ?? selectedCharacter.defaultExpressionID
        let routeMetadata = plan.presentationMetadata(
            characterID: selectedCharacter.id,
            expressionID: selectedPlanExpressionID
        )
        let routeSummary = plan.presentationSummary(
            character: selectedCharacter,
            expressionID: selectedPlanExpressionID
        )
        if selectedCharacter.id != plannedCharacter.id {
            fputs(
                "[LocalDeepSeek] 形态协调：沿用 quick 的 \(selectedCharacter.id)，plan 原选择为 \(plannedCharacter.id)\n",
                stderr
            )
        }
        let normalizedAction = normalizeNextAction(plan.nextAction)
        if normalizedAction == "quick_only", quickMessage != nil {
            fputs("[LocalDeepSeek] plan 决定 quick_only，本轮不再生成第二次回复\n", stderr)
            return LocalChatResult(
                sessionID: activeSessionID,
                userMessage: userMessage,
                quickReply: quickMessage,
                followUpReply: nil,
                nextAction: normalizedAction,
                assessment: plan.assessment
            )
        }

        if ["clarify", "interaction"].contains(normalizedAction), quickMessage != nil {
            let actionText = plannedActionReply(plan: plan, character: selectedCharacter)
            let actionMessage = database.addLocalMessage(
                sessionID: activeSessionID,
                role: .assistant,
                content: actionText,
                characterID: selectedCharacter.id,
                expressionID: selectedPlanExpressionID,
                model: "route-plan",
                routePlan: routeMetadata,
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
                    routeSummary: routeSummary,
                    knowledgeCards: []
                ),
                nextAction: normalizedAction,
                assessment: plan.assessment
            )
        }

        let memoryLimit = plan.needMoreMemories ? 16 : 8
        let memories = database.contextMemories(
            queryTerms: plan.memoryQueries,
            limit: memoryLimit
        )
        let knowledgeCards = Self.retrieveKnowledgeCards(
            queryTerms: plan.knowledgeNeeds + plan.knowledgeQueries,
            limit: 3
        )

        fputs("[LocalDeepSeek] 开始 requestDeepReply...\n", stderr)
        let rawDeepReply: LocalReplyDraft
        do {
            rawDeepReply = try await requestDeepReply(
                apiKey: apiKey,
                character: selectedCharacter,
                history: history,
                memories: memories,
                profiles: profiles,
                knowledgeCards: knowledgeCards,
                plan: plan,
                quickReplyText: quickReply?.reply
            )
            fputs("[LocalDeepSeek] requestDeepReply 成功, 回复长度: \(rawDeepReply.reply.count)\n", stderr)
        } catch {
            fputs("[LocalDeepSeek] requestDeepReply 失败: \(error)\n", stderr)
            if quickMessage != nil {
                return LocalChatResult(
                    sessionID: activeSessionID,
                    userMessage: userMessage,
                    quickReply: quickMessage,
                    followUpReply: nil,
                    nextAction: "quick_only_deep_failed",
                    assessment: plan.assessment
                )
            }
            throw error
        }

        let cleanedDeepReply = removingRepeatedQuickPrefix(
            rawDeepReply.reply,
            quickReply: quickReply?.reply
        )
        guard !cleanedDeepReply.isEmpty else {
            fputs("[LocalDeepSeek] 深度回复仅重复快速回应，本轮不再追加\n", stderr)
            return LocalChatResult(
                sessionID: activeSessionID,
                userMessage: userMessage,
                quickReply: quickMessage,
                followUpReply: nil,
                nextAction: "quick_only_deep_redundant",
                assessment: plan.assessment
            )
        }
        let deepReply = LocalReplyDraft(
            reply: cleanedDeepReply,
            characterID: selectedCharacter.id,
            expressionID: rawDeepReply.expressionID,
            retrievedMemories: memories,
            retrievedKnowledgeCards: knowledgeCards
        )
        
        let deepExpressionID = validExpressionID(deepReply.expressionID ?? plan.expressionID, for: selectedCharacter)
            ?? selectedPlanExpressionID
        let assistantMessage = database.addLocalMessage(
            sessionID: activeSessionID,
            role: .assistant,
            content: deepReply.reply,
            characterID: selectedCharacter.id,
            expressionID: deepExpressionID,
            model: "deepseek-chat",
            routePlan: plan.metadata,
            replyStage: "deep",
            knowledgeCards: knowledgeCards,
            retrievedMemories: memories
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
                replyStage: "deep",
                routeSummary: plan.presentationSummary(
                    character: selectedCharacter,
                    expressionID: deepExpressionID
                ),
                routePlan: plan.metadata,
                knowledgeCards: knowledgeCards,
                retrievedMemories: memories
            ),
            nextAction: "deep",
            assessment: plan.assessment
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
        var prompt = Self.routePlanPrompt
            .replacingOccurrences(of: "{character_text}", with: characterText)
            .replacingOccurrences(of: "{history_text}", with: historyText)
            .replacingOccurrences(of: "{profile_text}", with: profileText.isEmpty ? "暂无" : profileText)
            .replacingOccurrences(of: "{fallback_character_id}", with: fallbackCharacter.id)
        var content = try await requestPlanAPI(
            apiKey: apiKey,
            prompt: prompt,
            maxTokens: 4000,
            thinking: true
        )
        fputs("[LocalDeepSeek] requestPlan: content 长度: \(content.count)\n", stderr)

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

        var parsedDict: [String: Any]?
        for attempt in 1...3 {
            parsedDict = parseJSONObject(content)
            if parsedDict != nil {
                break
            }
            fputs("[LocalDeepSeek] requestPlan: JSON 解析失败 (attempt \(attempt)), content: \(content)\n", stderr)
            if attempt < 3 {
                fputs("[LocalDeepSeek] requestPlan: 第 \(attempt) 次解析失败，重试 API 请求...\n", stderr)
                content = try await requestPlanAPI(
                    apiKey: apiKey,
                    prompt: prompt,
                    maxTokens: 2200,
                    thinking: false
                )
                fputs("[LocalDeepSeek] requestPlan 重试: content 长度: \(content.count)\n", stderr)
            }
        }

        guard let dict = parsedDict else {
            fputs("[LocalDeepSeek] requestPlan: 所有 \(3) 次尝试均失败\n", stderr)
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
            actionReply: stringFromDict(dict, "action_reply"),
            historyTurnsNeeded: {
                if let v = dict["history_turns_needed"] as? Int { return max(0, min(20, v)) }
                if let v = dict["history_turns_needed"] as? Double { return max(0, min(20, Int(v))) }
                if let v = dict["history_turns_needed"] as? NSNumber { return max(0, min(20, v.intValue)) }
                return 5
            }(),
            needStateProfiles: dict["need_state_profiles"] as? Bool ?? true,
            needMoreMemories: dict["need_more_memories"] as? Bool ?? false,
            contextStrategy: {
                let v = stringFromDict(dict, "context_strategy")
                return ["focus_current", "balanced", "history_heavy"].contains(v) ? v : "balanced"
            }()
        )
    }

    private func buildJSONRequest(
        apiKey: String,
        messages: [DeepSeekMessage],
        maxTokens: Int,
        thinking: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
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
        let characterOptions = CompanionFixtures.characters.map { option in
            let expressions = option.expressions.map(\.id).joined(separator: ", ")
            return "- \(option.id)（\(option.name)）：\(option.tagline)；可用表情：\(expressions)"
        }.joined(separator: "\n")
        var prompt = Self.quickReplyPrompt
            .replacingOccurrences(of: "{last_user_message}", with: history.last?.content ?? "")
            .replacingOccurrences(of: "{character_options}", with: characterOptions)
            .replacingOccurrences(of: "{current_character_id}", with: character.id)
            .replacingOccurrences(of: "{current_character_name}", with: character.name)
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
        if let parsed = parseReplyPayload(content) {
            let selectedCharacter = CompanionFixtures.character(id: parsed.characterID) ?? character
            return LocalReplyDraft(
                reply: parsed.reply,
                characterID: selectedCharacter.id,
                expressionID: validExpressionID(parsed.expressionID, for: selectedCharacter)
                    ?? selectedCharacter.defaultExpressionID,
                retrievedMemories: [],
                retrievedKnowledgeCards: []
            )
        }
        let fallbackText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackText.isEmpty {
            fputs("[LocalDeepSeek] requestQuickReply: 结构化回复解析失败，使用纯文本兜底\n", stderr)
            return LocalReplyDraft(
                reply: fallbackText,
                characterID: character.id,
                expressionID: character.defaultExpressionID,
                retrievedMemories: [],
                retrievedKnowledgeCards: []
            )
        }
        fputs("[LocalDeepSeek] requestQuickReply: 结构化回复解析失败且内容为空\n", stderr)
        throw LocalDeepSeekError.invalidResponse
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
        fputs("[LocalDeepSeek] requestDeepReply: 历史消息数: \(history.count), 规划历史轮数: \(plan.historyTurnsNeeded)\n", stderr)
        let historySliceCount = plan.historyTurnsNeeded > 0 ? min(plan.historyTurnsNeeded * 2, history.count) : 0
        let recentHistory = history.suffix(historySliceCount).map { msg in
            let roleLabel = msg.role == .user ? "用户" : character.name
            let content = msg.content.count > 1200 ? String(msg.content.prefix(1200)) + "…" : msg.content
            return "\(roleLabel)：\(content)"
        }.joined(separator: "\n")
        let promptWithHistory = recentHistory.isEmpty ? prompt : (prompt + "\n\n当前对话历史：\n\(recentHistory)\n")
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
        if let parsed = parseReplyPayload(content) {
            fputs("[LocalDeepSeek] requestDeepReply: 结构化回复解析成功\n", stderr)
            return LocalReplyDraft(
                reply: parsed.reply,
                characterID: character.id,
                expressionID: parsed.expressionID ?? plan.expressionID,
                retrievedMemories: memories,
                retrievedKnowledgeCards: knowledgeCards
            )
        }
        let fallbackText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackText.isEmpty {
            fputs("[LocalDeepSeek] requestDeepReply: 结构化回复解析失败，使用纯文本兜底\n", stderr)
            return LocalReplyDraft(
                reply: fallbackText,
                characterID: character.id,
                expressionID: plan.expressionID,
                retrievedMemories: memories,
                retrievedKnowledgeCards: knowledgeCards
            )
        }
        fputs("[LocalDeepSeek] requestDeepReply: 结构化回复解析失败且内容为空\n", stderr)
        throw LocalDeepSeekError.invalidResponse
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
        var fullPrompt = Self.sessionExtractionPrompt
            .replacingOccurrences(of: "{transcript}", with: transcript)
            .replacingOccurrences(of: "{profile_text}", with: profileText.isEmpty ? "暂无" : profileText)
        let request = try buildJSONRequest(
            apiKey: apiKey,
            messages: [
                DeepSeekMessage(
                    role: "user",
                    content: fullPrompt
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
        guard let content = payload.choices.first?.message.content else {
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
        let profileText = plan.needStateProfiles ? profiles.map { "- [\($0.domain)] 阶段：\($0.stage)；摘要：\($0.summary)；趋势：\($0.trend)；强度：\($0.intensity)/10" }.joined(separator: "\n") : ""
        let knowledgeText = knowledgeCards.map { "- \($0.title)：\($0.concept)" }.joined(separator: "\n")
        let characterProfile = "你是\(character.name)，\(character.tagline)。\(character.voice)"

        let rolePlanText = """
        - 用户状态：\(plan.userState)
        - 核心需要：\(plan.coreNeed)
        - 风险等级：\(plan.riskLevel)
        - 回复模式：\(plan.responseMode)
        - 写作方向：\(plan.responseGuidance)
        """

        let handoffText = quickReplyText.map { text in
            Self.quickReplyHandoffPrompt
                .replacingOccurrences(of: "{quick_reply_text}", with: text)
        } ?? ""

        let expressionID = plan.expressionID.isEmpty ? character.defaultExpressionID : plan.expressionID
        let expressionOptions = character.expressions.map(\.id).joined(separator: ", ")
        let rabbitInstruction = Self.rabbitResponseInstructionPrompt
            .replacingOccurrences(of: "{character_name}", with: character.name)
            .replacingOccurrences(of: "{expression_id}", with: expressionID)
            .replacingOccurrences(of: "{expression_options}", with: expressionOptions)

        return Self.personaPrompt
            .replacingOccurrences(of: "{character_profile}", with: characterProfile)
            .replacingOccurrences(of: "{current_character_name}", with: character.name)
            .replacingOccurrences(of: "{character_tagline}", with: character.tagline)
            .replacingOccurrences(of: "{character_voice}", with: character.voice)
            .replacingOccurrences(of: "{quick_reply_handoff}", with: handoffText)
            .replacingOccurrences(of: "{rabbit_response_instruction}", with: rabbitInstruction)
            .replacingOccurrences(of: "{role_plan}", with: rolePlanText)
            .replacingOccurrences(of: "{memories}", with: memoryText.isEmpty ? "暂无" : memoryText)
            .replacingOccurrences(of: "{state_profiles}", with: profileText.isEmpty ? "当前不需要长期状态画像。" : profileText)
            .replacingOccurrences(of: "{conversation_history_section}", with: "")
            .replacingOccurrences(of: "{knowledge_cards}", with: knowledgeText.isEmpty ? "暂无" : knowledgeText)
    }

    private func requestJSON<Response: Decodable>(
        apiKey: String,
        messages: [DeepSeekMessage],
        maxTokens: Int,
        thinking: Bool
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
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
