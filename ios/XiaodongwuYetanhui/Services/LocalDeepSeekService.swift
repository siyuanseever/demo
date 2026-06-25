import Foundation

struct LocalChatResult {
    let sessionID: String
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
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
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: [String]
    let supportStrategy: String

    enum CodingKeys: String, CodingKey {
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
        let extraction = try await requestSessionExtraction(apiKey: apiKey, messages: messages)
        database.addLocalJournal(sessionID: sessionID, journal: extraction.journal)
        database.addLocalMemories(sessionID: sessionID, memories: extraction.memories)
        database.upsertLocalStateProfiles(sessionID: sessionID, profiles: extraction.stateProfiles)
        database.endLocalSession(sessionID)
        self.sessionID = nil
        return SessionCloseSummary(
            journalSummary: extraction.journal.summary,
            memoryCount: extraction.memories.count,
            stateProfileCount: extraction.stateProfiles.count
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
        let memories = database.memories(limit: 12)
        let profiles = database.stateProfiles(limit: 8)
        let reply = try await requestReply(
            apiKey: apiKey,
            character: character,
            history: history,
            memories: memories,
            profiles: profiles
        )
        let assistantMessage = database.addLocalMessage(
            sessionID: activeSessionID,
            role: .assistant,
            content: reply,
            characterID: character.id,
            expressionID: character.defaultExpressionID,
            model: "deepseek-chat"
        )
        return LocalChatResult(
            sessionID: activeSessionID,
            userMessage: userMessage,
            assistantMessage: assistantMessage
        )
    }

    private func requestReply(
        apiKey: String,
        character: CompanionCharacter,
        history: [ChatMessage],
        memories: [MemoryEntry],
        profiles: [StateProfile]
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekRequest(
                model: "deepseek-chat",
                messages: [
                    DeepSeekMessage(role: "system", content: systemPrompt(
                        character: character,
                        memories: memories,
                        profiles: profiles
                    )),
                ] + history.map {
                    DeepSeekMessage(
                        role: $0.role == .user ? "user" : "assistant",
                        content: $0.content
                    )
                },
                temperature: 0.7,
                maxTokens: 1200,
                stream: false
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
        guard let content = payload.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw LocalDeepSeekError.invalidResponse
        }
        return content
    }

    private func requestSessionExtraction(
        apiKey: String,
        messages: [ChatMessage]
    ) async throws -> LocalSessionExtraction {
        let transcript = messages.map {
            "\($0.role == .user ? "用户" : "陪伴者")：\($0.content)"
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
                        state_profiles 只在证据足够时更新，0-4 条。
                        mood_score 使用 -5 到 5；confidence 使用 0 到 1；importance 使用 1 到 5。
                        """
                    ),
                    DeepSeekMessage(
                        role: "user",
                        content: """
                        对话：
                        \(transcript)

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
        profiles: [StateProfile]
    ) -> String {
        let memoryText = memories.map { "- \($0.content)" }.joined(separator: "\n")
        let profileText = profiles.map { "- \($0.domain)：\($0.summary)" }.joined(separator: "\n")
        return """
        你是森森物语里的\(character.name)，是一位温和、清醒、有边界的自我理解型心理陪伴者，不是治疗师，也不做诊断。

        回应要求：
        - 优先复述和澄清用户的感受，不急着解释。
        - 每次最多引入一个心理学视角。
        - 给出一个很小、现实、低压力的下一步。
        - 不制造依赖，不强行积极。
        - 如出现明确自伤、他伤或现实危险，优先建议联系当地紧急服务和可信任的现实支持。
        - 使用中文，通常 3-7 段。

        当前角色气质：\(character.tagline)。\(character.voice)

        手机本地保存的长期记忆：
        \(memoryText.isEmpty ? "暂无" : memoryText)

        手机本地保存的长期状态：
        \(profileText.isEmpty ? "暂无" : profileText)
        """
    }
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [DeepSeekMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    var responseFormat: DeepSeekResponseFormat? = nil

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case responseFormat = "response_format"
    }
}

private struct DeepSeekResponseFormat: Encodable {
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
