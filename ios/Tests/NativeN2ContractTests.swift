import Darwin
import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

@main
private struct NativeN2ContractTests {
    static func main() async {
        do {
            try testReplyStagePersistence()
            try testDashboardDataRoundTrip()
            try testSessionDeletionCascade()
            try testConversationTurnGrouping()
            try await testWeeklyFlowRoundTrip()
            try await testDirectQuickPlanDeepPipeline()
            try await testDirectQuickOnlyPipeline()
            try await testTenTurnDirectPipeline()
            print("Native N2/N3 contract tests passed")
        } catch {
            fputs("Native N2/N3 contract tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testReplyStagePersistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-n2-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try SQLiteDatabase(databaseURL: url)
        let sessionID = database.createLocalSession()
        try expect(database.sessionExists(sessionID), "created session must be discoverable")
        try expect(!database.sessionExists("missing-session"), "missing session was reported as available")
        _ = database.addLocalMessage(sessionID: sessionID, role: .user, content: "测试问题")
        _ = database.addLocalMessage(
            sessionID: sessionID,
            role: .assistant,
            content: "快速回应",
            model: "quick",
            replyStage: "quick"
        )
        _ = database.addLocalMessage(
            sessionID: sessionID,
            role: .assistant,
            content: "深度回应",
            model: "deepseek-chat",
            replyStage: "deep"
        )

        let messages = database.messages(sessionID: sessionID)
        try expect(messages.count == 3, "expected three persisted messages")
        try expect(messages[1].replyStage == "quick", "quick stage was not persisted")
        try expect(messages[2].replyStage == "deep", "deep stage was not persisted")

        for index in 0..<300 {
            _ = database.addLocalMessage(
                sessionID: sessionID,
                role: .assistant,
                content: "bounded message \(index)"
            )
        }
        try expect(database.messages(sessionID: sessionID, limit: 120).count == 120, "message fetch must remain bounded")
    }

    private static func testConversationTurnGrouping() throws {
        let messages = [
            ChatMessage(id: "u1", role: .user, content: "第一问", characterID: nil, createdAt: ""),
            ChatMessage(id: "q1", role: .assistant, content: "快速", characterID: "yoyo", createdAt: "", replyStage: "quick"),
            ChatMessage(id: "d1", role: .assistant, content: "深入", characterID: "momo", createdAt: "", replyStage: "deep"),
            ChatMessage(id: "u2", role: .user, content: "第二问", characterID: nil, createdAt: ""),
            ChatMessage(id: "q2", role: .assistant, content: "第二轮", characterID: "yoyo", createdAt: "", replyStage: "quick"),
        ]
        let turns = NativeConversationTurn.build(from: messages)
        try expect(turns.count == 2, "expected two conversation turns")
        try expect(turns[0].replies.map(\.replyStage) == ["quick", "deep"], "quick and deep must share one turn")
        try expect(turns[1].replies.count == 1, "second turn reply count mismatch")
    }

    private static func testDashboardDataRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-data-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try SQLiteDatabase(databaseURL: url)
        let sessionID = database.createLocalSession()
        database.addLocalJournal(
            sessionID: sessionID,
            journal: LocalJournalDraft(
                summary: "本轮总结",
                emotionCurve: ["紧张", "稍微平稳"],
                keywords: ["边界", "休息"],
                insights: ["压力与边界有关"],
                suggestedNextStep: "先停十分钟",
                moodScore: -2,
                dominantEmotion: "疲惫"
            )
        )
        database.addLocalMemories(
            sessionID: sessionID,
            memories: [
                LocalMemoryDraft(
                    category: "emotion_pattern",
                    subcategory: "stress",
                    keywords: ["压力"],
                    content: "高压时更需要清晰边界",
                    evidence: "本轮明确表达",
                    confidence: 0.86,
                    importance: 4
                )
            ]
        )
        database.upsertLocalStateProfiles(
            sessionID: sessionID,
            profiles: [
                LocalStateProfileDraft(
                    action: "update",
                    domain: "emotion_regulation",
                    stage: "正在觉察",
                    summary: "能够识别压力来源",
                    intensity: 6,
                    trend: "改善",
                    confidence: 0.78,
                    evidence: ["能说出身体紧张"],
                    supportStrategy: "先确认身体感受"
                )
            ]
        )

        let journal = try require(database.journals().first, "journal was not persisted")
        try expect(journal.sessionID == sessionID, "journal session relation was lost")
        try expect(journal.summary == "本轮总结", "journal summary was lost")
        try expect(journal.emotionCurve == ["紧张", "稍微平稳"], "emotion curve was lost")
        try expect(journal.keywords == ["边界", "休息"], "journal keywords were lost")
        try expect(journal.insights == ["压力与边界有关"], "journal insights were lost")
        try expect(journal.suggestedNextStep == "先停十分钟", "journal next step was lost")
        try expect(journal.moodScore == -2, "journal mood score was lost")
        try expect(journal.dominantEmotion == "疲惫", "dominant emotion was lost")

        let memory = try require(database.memories().first, "memory was not persisted")
        try expect(memory.category == "emotion_pattern", "memory category was lost")
        try expect(memory.subcategory == "stress", "memory subcategory was lost")
        try expect(memory.keywords == ["压力"], "memory keywords were lost")
        try expect(memory.evidence == "本轮明确表达", "memory evidence was lost")
        try expect(memory.sourceSessionID == sessionID, "memory session relation was lost")
        try expect(memory.importance == 4, "memory importance was lost")

        let profile = try require(database.stateProfiles().first, "state profile was not persisted")
        try expect(profile.domain == "emotion_regulation", "state domain was lost")
        try expect(profile.stage == "正在觉察", "state stage was lost")
        try expect(profile.summary == "能够识别压力来源", "state summary was lost")
        try expect(profile.intensity == 6, "state intensity was lost")
        try expect(profile.trend == "改善", "state trend was lost")
        try expect(abs(profile.confidence - 0.78) < 0.001, "state confidence was lost")
        try expect(profile.evidence.contains("能说出身体紧张"), "state evidence was lost")
        try expect(profile.supportStrategy == "先确认身体感受", "support strategy was lost")
        try expect(profile.sourceSessionID == sessionID, "state session relation was lost")

        let nextSessionID = database.createLocalSession()
        database.upsertLocalStateProfiles(
            sessionID: nextSessionID,
            profiles: [
                LocalStateProfileDraft(
                    action: "update",
                    domain: "emotion_regulation",
                    stage: "逐渐稳定",
                    summary: "开始主动安排恢复时间",
                    intensity: 4,
                    trend: "softening",
                    confidence: 0.82,
                    evidence: ["主动提出先休息"],
                    supportStrategy: "继续保留恢复空间"
                )
            ]
        )
        let currentProfile = try require(database.stateProfiles().first, "updated state profile was not persisted")
        try expect(database.stateProfiles().count == 1, "current state must remain one row per domain")
        try expect(currentProfile.summary == "开始主动安排恢复时间", "current state did not update")
        let versions = database.stateProfileVersions()
        try expect(versions.count == 2, "state history must retain both versions")
        try expect(versions.first?.sourceSessionID == nextSessionID, "latest state version lost its source session")
        try expect(versions.last?.sourceSessionID == sessionID, "earlier state version was overwritten")

        database.deleteSession(nextSessionID)
        let restoredProfile = try require(database.stateProfiles().first, "state profile did not fall back after deleting latest source")
        try expect(restoredProfile.summary == "能够识别压力来源", "state profile did not restore the previous version")
        try expect(restoredProfile.sourceSessionID == sessionID, "restored state profile lost its source session")
        try expect(database.stateProfileVersions().count == 1, "deleted session state version remained in history")
    }

    private static func testSessionDeletionCascade() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-delete-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try SQLiteDatabase(databaseURL: url)
        let sessionID = database.createLocalSession()
        _ = database.addLocalMessage(sessionID: sessionID, role: .user, content: "准备删除")
        database.addLocalJournal(
            sessionID: sessionID,
            journal: LocalJournalDraft(
                summary: "删除测试",
                emotionCurve: [],
                keywords: [],
                insights: [],
                suggestedNextStep: "",
                moodScore: 0,
                dominantEmotion: ""
            )
        )
        database.addLocalMemories(
            sessionID: sessionID,
            memories: [
                LocalMemoryDraft(
                    category: "test",
                    subcategory: "delete",
                    keywords: [],
                    content: "关联记忆",
                    evidence: "测试",
                    confidence: 1,
                    importance: 1
                )
            ]
        )
        database.upsertLocalStateProfiles(
            sessionID: sessionID,
            profiles: [
                LocalStateProfileDraft(
                    action: "update",
                    domain: "delete_test",
                    stage: "",
                    summary: "关联状态",
                    intensity: 1,
                    trend: "",
                    confidence: 1,
                    evidence: [],
                    supportStrategy: ""
                )
            ]
        )

        database.deleteSession(sessionID)

        try expect(database.sessions().allSatisfy { $0.id != sessionID }, "session deletion failed")
        try expect(database.messages(sessionID: sessionID).isEmpty, "session messages were not deleted")
        try expect(database.journals().allSatisfy { $0.sessionID != sessionID }, "session journal was not deleted")
        try expect(database.memories().allSatisfy { $0.sourceSessionID != sessionID }, "session memory was not deleted")
        try expect(database.stateProfiles().allSatisfy { $0.sourceSessionID != sessionID }, "session state profile was not deleted")
        try expect(database.stateProfileVersions().allSatisfy { $0.sourceSessionID != sessionID }, "session state version was not deleted")
    }

    private static func testWeeklyFlowRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-flow-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try SQLiteDatabase(databaseURL: url)
        let sessionID = database.createLocalSession()
        database.addLocalJournal(
            sessionID: sessionID,
            journal: LocalJournalDraft(
                summary: "最近有些疲惫，也开始注意自己的边界",
                emotionCurve: ["紧绷", "清晰"],
                keywords: ["压力", "边界"],
                insights: ["先停下来更容易看清需要"],
                suggestedNextStep: "留十分钟休息",
                moodScore: -1,
                dominantEmotion: "疲惫"
            )
        )
        database.addLocalMemories(
            sessionID: sessionID,
            memories: [
                LocalMemoryDraft(
                    category: "emotion_pattern",
                    subcategory: "stress",
                    keywords: ["压力", "边界"],
                    content: "高压时更需要清晰边界",
                    evidence: "近期夜谈",
                    confidence: 0.85,
                    importance: 4
                )
            ]
        )

        let service = LocalDeepSeekService(session: .shared, endpoint: try fixtureEndpoint())
        let insight = try await service.generateWeeklyFlowInsight(
            apiKey: "fixture-key",
            database: database
        )
        database.saveStarMapInsight(insight)

        let persisted = try require(database.latestStarMapInsight(), "weekly flow was not persisted")
        try expect(persisted.primaryGoalTitle == "给自己留一段安静时间", "primary flow goal was lost")
        try expect(persisted.recentEmotionTags == ["疲惫", "觉察"], "flow emotion tags were lost")
        try expect(persisted.memoryCues == ["高压时更需要清晰边界"], "flow memory cues were lost")
        try expect(persisted.primaryGoalNextStep == "今晚留十分钟不处理任务", "flow next step was lost")
        try expect(!persisted.isMockInsight, "persisted flow unexpectedly fell back to mock data")
    }

    @MainActor
    private static func testDirectQuickPlanDeepPipeline() async throws {
        let endpoint = try fixtureEndpoint()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-direct-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try SQLiteDatabase(databaseURL: url)
        let service = LocalDeepSeekService(session: .shared, endpoint: endpoint)
        var callbackStages: [String] = []
        let result = try await service.send(
            text: "测试",
            character: CompanionFixtures.characters[0],
            apiKey: "fixture-key",
            database: database
        ) { message in
            callbackStages.append(message.replyStage)
        }

        try expect(callbackStages == ["quick"], "quick callback must arrive before pipeline completion")
        try expect(result.nextAction == "deep", "plan should choose deep")
        try expect(result.quickReply?.content == "先接住你", "quick reply was not parsed")
        try expect(result.followUpReply?.content == "再一起看深一点", "deep reply was not parsed")
        try expect(result.followUpReply?.replyStage == "deep", "deep stage is missing")
        try expect(result.assessment?.nextAction == "deep", "plan assessment was not decoded")

        let persisted = database.messages(sessionID: result.sessionID)
        try expect(persisted.map(\.replyStage).contains("quick"), "quick reply was not persisted")
        try expect(persisted.map(\.replyStage).contains("deep"), "deep reply was not persisted")
    }

    @MainActor
    private static func testDirectQuickOnlyPipeline() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-quick-only-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try SQLiteDatabase(databaseURL: url)
        let service = LocalDeepSeekService(session: .shared, endpoint: try fixtureEndpoint())
        var callbackCount = 0
        let result = try await service.send(
            text: "简单问候",
            character: CompanionFixtures.characters[0],
            apiKey: "fixture-key",
            database: database
        ) { _ in
            callbackCount += 1
        }

        try expect(callbackCount == 1, "quick-only must still deliver one quick callback")
        try expect(result.nextAction == "quick_only", "plan should choose quick_only")
        try expect(result.quickReply != nil, "quick-only lost quick reply")
        try expect(result.followUpReply == nil, "quick-only unexpectedly generated deep reply")
        try expect(database.messages(sessionID: result.sessionID).count == 2, "quick-only should persist user + quick")
    }

    @MainActor
    private static func testTenTurnDirectPipeline() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensen-native-ten-turn-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try SQLiteDatabase(databaseURL: url)
        let service = LocalDeepSeekService(session: .shared, endpoint: try fixtureEndpoint())
        var callbackCount = 0
        var sessionID = ""
        for index in 1...10 {
            let result = try await service.send(
                text: "连续回归第 \(index) 轮",
                character: CompanionFixtures.characters[0],
                apiKey: "fixture-key",
                database: database
            ) { _ in
                callbackCount += 1
            }
            sessionID = result.sessionID
            try expect(result.quickReply != nil, "turn \(index) lost quick reply")
            try expect(result.followUpReply?.replyStage == "deep", "turn \(index) lost deep reply")
        }

        let persisted = database.messages(sessionID: sessionID)
        try expect(callbackCount == 10, "ten-turn run delivered \(callbackCount) quick callbacks")
        try expect(persisted.count == 30, "ten-turn run should persist 30 messages, got \(persisted.count)")
        try expect(persisted.filter { $0.replyStage == "quick" }.count == 10, "ten-turn quick count mismatch")
        try expect(persisted.filter { $0.replyStage == "deep" }.count == 10, "ten-turn deep count mismatch")
    }

    private static func fixtureEndpoint() throws -> URL {
        guard
            let rawURL = ProcessInfo.processInfo.environment["NATIVE_N2_FIXTURE_URL"],
            let endpoint = URL(string: rawURL)?.appendingPathComponent("chat/completions")
        else {
            throw TestFailure.assertion("NATIVE_N2_FIXTURE_URL is missing")
        }
        return endpoint
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure.assertion(message)
        }
    }

    private static func require<Value>(_ value: Value?, _ message: String) throws -> Value {
        guard let value else { throw TestFailure.assertion(message) }
        return value
    }
}
