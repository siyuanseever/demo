import Darwin
import Foundation

private enum SmokeFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

@main
private struct NativeDeepSeekSmoke {
    @MainActor
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Native DeepSeek smoke failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        guard
            let apiKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            throw SmokeFailure.assertion("DEEPSEEK_API_KEY is missing")
        }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-deepseek-smoke-\(UUID().uuidString).db")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 95
        configuration.timeoutIntervalForResource = 180
        let service = LocalDeepSeekService(session: URLSession(configuration: configuration))
        let database = try SQLiteDatabase(databaseURL: databaseURL)
        let startedAt = Date()
        var quickArrival: Date?
        var quickMessageID: String?

        let result = try await service.send(
            text: "我最近一边很想停下来休息，一边只要没有继续推进事情就会自责。我知道自己已经很累了，却仍然觉得休息是在逃避。请先接住此刻的感受，再帮我深入看一看这个矛盾可能来自哪里。",
            character: CompanionFixtures.characters[0],
            apiKey: apiKey,
            database: database
        ) { message in
            quickArrival = Date()
            quickMessageID = message.id
        }
        let completedAt = Date()

        guard let quickReply = result.quickReply else {
            throw SmokeFailure.assertion("quick reply was not returned")
        }
        guard quickMessageID == quickReply.id, quickArrival != nil else {
            throw SmokeFailure.assertion("quick callback was not delivered")
        }
        try expectCleanReply(quickReply.content, stage: "quick")
        try expectValidPresentation(quickReply, stage: "quick")
        if let followUp = result.followUpReply {
            try expectCleanReply(followUp.content, stage: followUp.replyStage)
            try expectValidPresentation(followUp, stage: followUp.replyStage)
        }

        let persisted = database.messages(sessionID: result.sessionID)
        guard persisted.first?.role == .user else {
            throw SmokeFailure.assertion("user message was not persisted first")
        }
        guard persisted.contains(where: { $0.id == quickReply.id && $0.replyStage == "quick" }) else {
            throw SmokeFailure.assertion("persisted quick reply is missing")
        }
        if result.followUpReply != nil,
           !persisted.contains(where: { $0.replyStage == "deep" || !$0.action.isEmpty }) {
            throw SmokeFailure.assertion("persisted follow-up reply is missing")
        }

        let quickSeconds = quickArrival?.timeIntervalSince(startedAt) ?? 0
        let totalSeconds = completedAt.timeIntervalSince(startedAt)
        guard quickSeconds <= totalSeconds else {
            throw SmokeFailure.assertion("quick callback arrived after pipeline completion")
        }

        let quickDuration = String(format: "%.2f", quickSeconds)
        let totalDuration = String(format: "%.2f", totalSeconds)
        print("Native DeepSeek smoke passed")
        print("quick=\(quickDuration)s total=\(totalDuration)s")
        print("next_action=\(result.nextAction) persisted_messages=\(persisted.count) follow_up=\(result.followUpReply != nil)")
        let quickExpression = quickReply.expressionID.isEmpty ? "missing" : quickReply.expressionID
        let followUpExpression = result.followUpReply?.expressionID.isEmpty == false
            ? result.followUpReply?.expressionID ?? "none"
            : "none"
        print(
            "quick_presentation=\(quickReply.characterID ?? "missing")/\(quickExpression) "
                + "follow_up_presentation=\(result.followUpReply?.characterID ?? "none")/\(followUpExpression)"
        )
    }

    private static func expectCleanReply(_ content: String, stage: String) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SmokeFailure.assertion("\(stage) reply is empty")
        }
        let looksLikeRawPayload = trimmed.hasPrefix("{")
            && trimmed.contains("\"reply\"")
            && trimmed.contains("expression_id")
        guard !looksLikeRawPayload else {
            throw SmokeFailure.assertion("\(stage) reply leaked its JSON envelope")
        }
    }

    private static func expectValidPresentation(_ message: ChatMessage, stage: String) throws {
        guard let character = CompanionFixtures.character(id: message.characterID) else {
            throw SmokeFailure.assertion("\(stage) reply has an unknown character_id")
        }
        guard character.expressions.contains(where: { $0.id == message.expressionID }) else {
            throw SmokeFailure.assertion("\(stage) reply has an expression outside \(character.id)")
        }
    }
}
