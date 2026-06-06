import Foundation

struct ChatServiceResponse {
    let reply: String
    let characterID: String?
    let groupMessages: [ChatServiceGroupMessage]
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
}

struct SessionCloseSummary {
    let journalSummary: String
    let memoryCount: Int
    let stateProfileCount: Int
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
            _ = try await currentSessionID()
            return BackendConnectionStatus(
                state: .online,
                baseURL: backendURLDescription,
                detail: "本地后端可以创建会话，iOS 对话会优先走真实 Web 路由。",
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
            return ChatServiceResponse(
                reply: response.reply,
                characterID: response.character?.id ?? character.id,
                groupMessages: (response.groupMessages ?? []).map {
                    ChatServiceGroupMessage(
                        role: $0.role,
                        text: $0.text,
                        action: $0.action ?? "",
                        characterID: $0.character?.id
                    )
                },
                usedFallback: false,
                notice: nil,
                backendURL: backendURLDescription,
                errorDetail: nil
            )
        } catch {
            return ChatServiceResponse(
                reply: fallbackReply ?? Self.fallbackReply(for: text, character: character),
                characterID: character.id,
                groupMessages: [],
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
        request.timeoutInterval = 12
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
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
            // 真机用局域网 IP
            return URL(string: "http://192.168.2.124:8765")!
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

private struct SessionResponseBody: Decodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
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
    let groupMessages: [GroupMessageResponseBody]?

    enum CodingKeys: String, CodingKey {
        case reply
        case character
        case groupMessages = "group_messages"
    }
}

private struct GroupMessageResponseBody: Decodable {
    let role: String
    let text: String
    let action: String?
    let character: ResponseCharacter?
}

private struct ResponseCharacter: Decodable {
    let id: String
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
