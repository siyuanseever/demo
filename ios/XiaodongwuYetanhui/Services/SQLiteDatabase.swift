import Foundation
import SQLite3

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init() throws {
        let databaseURL = try Self.preparedDatabaseURL()
        if sqlite3_open(databaseURL.path, &handle) != SQLITE_OK {
            throw DatabaseError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func count(table: String) -> Int {
        guard Self.allowedTables.contains(table) else { return 0 }
        let rows = rows(sql: "SELECT COUNT(*) AS count FROM \(table)")
        return Int(rows.first?["count"] ?? "0") ?? 0
    }

    func recentMessages(limit: Int = 16) -> [ChatMessage] {
        rows(
            sql: """
            SELECT id, role, content, metadata, created_at
            FROM messages
            ORDER BY created_at DESC
            LIMIT ?
            """,
            bindings: [String(limit)]
        )
        .reversed()
        .map { row in
            let metadata = Self.metadataObject(from: row["metadata"] ?? "{}")
            return ChatMessage(
                id: row["id"] ?? UUID().uuidString,
                role: MessageRole(rawValue: row["role"] ?? "") ?? .assistant,
                content: row["content"] ?? "",
                characterID: metadata["character_id"] as? String,
                createdAt: row["created_at"] ?? "",
                groupRole: metadata["group_role"] as? String ?? "",
                action: metadata["action"] as? String ?? "",
                expressionID: metadata["expression_id"] as? String ?? "",
                routeSummary: Self.routeSummary(from: metadata["route_plan"] as? [String: Any]),
                knowledgeCards: Self.knowledgeCards(from: metadata["knowledge_card_ids"])
            )
        }
    }

    func sessions(limit: Int = 80) -> [SessionSummary] {
        rows(
            sql: """
            SELECT
                sessions.id,
                sessions.created_at,
                sessions.ended_at,
                COUNT(messages.id) AS message_count,
                COALESCE(
                    (
                        SELECT content
                        FROM messages AS preview_messages
                        WHERE preview_messages.session_id = sessions.id
                        ORDER BY preview_messages.created_at DESC
                        LIMIT 1
                    ),
                    ''
                ) AS preview
            FROM sessions
            LEFT JOIN messages ON messages.session_id = sessions.id
            GROUP BY sessions.id
            HAVING COUNT(messages.id) > 0
            ORDER BY sessions.created_at DESC
            LIMIT ?
            """,
            bindings: [String(limit)]
        )
        .map { row in
            SessionSummary(
                id: row["id"] ?? UUID().uuidString,
                createdAt: row["created_at"] ?? "",
                endedAt: row["ended_at"] ?? "",
                messageCount: Int(row["message_count"] ?? "0") ?? 0,
                preview: row["preview"] ?? ""
            )
        }
    }

    func upsertRemoteSession(_ session: RemoteSessionSummary) {
        execute(
            sql: """
            INSERT INTO sessions (id, created_at, ended_at)
            VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                created_at = excluded.created_at,
                ended_at = excluded.ended_at
            """,
            bindings: [
                session.id,
                session.createdAt,
                session.endedAt,
            ]
        )
    }

    func upsertRemoteMessages(_ messages: [RemoteChatMessage]) {
        for message in messages {
            execute(
                sql: """
                INSERT INTO messages (id, session_id, role, content, model, metadata, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    session_id = excluded.session_id,
                    role = excluded.role,
                    content = excluded.content,
                    model = excluded.model,
                    metadata = excluded.metadata,
                    created_at = excluded.created_at
                """,
                bindings: [
                    message.id,
                    message.sessionID,
                    message.role,
                    message.content,
                    message.model,
                    Self.metadataString(from: message),
                    message.createdAt,
                ]
            )
        }
    }

    func upsertRemoteMemories(_ memories: [RemoteMemory]) {
        for memory in memories {
            execute(
                sql: """
                INSERT INTO memories (
                    id, user_id, category, subcategory, keywords, status, content,
                    evidence, confidence, importance, source_session_id, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    user_id = excluded.user_id,
                    category = excluded.category,
                    subcategory = excluded.subcategory,
                    keywords = excluded.keywords,
                    status = excluded.status,
                    content = excluded.content,
                    evidence = excluded.evidence,
                    confidence = excluded.confidence,
                    importance = excluded.importance,
                    source_session_id = excluded.source_session_id,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at
                """,
                bindings: [
                    memory.id,
                    memory.userID,
                    memory.category,
                    memory.subcategory,
                    Self.jsonString(from: memory.keywords),
                    memory.status,
                    memory.content,
                    memory.evidence,
                    String(memory.confidence),
                    String(memory.importance),
                    memory.sourceSessionID,
                    memory.createdAt,
                    memory.updatedAt,
                ]
            )
        }
    }

    func upsertRemoteJournals(_ journals: [RemoteJournal]) {
        for journal in journals {
            execute(
                sql: """
                INSERT INTO journals (
                    id, session_id, summary, emotion_curve, keywords, insights,
                    suggested_next_step, mood_score, dominant_emotion, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    session_id = excluded.session_id,
                    summary = excluded.summary,
                    emotion_curve = excluded.emotion_curve,
                    keywords = excluded.keywords,
                    insights = excluded.insights,
                    suggested_next_step = excluded.suggested_next_step,
                    mood_score = excluded.mood_score,
                    dominant_emotion = excluded.dominant_emotion,
                    created_at = excluded.created_at
                """,
                bindings: [
                    journal.id,
                    journal.sessionID,
                    journal.summary,
                    Self.jsonString(from: journal.emotionCurve),
                    Self.jsonString(from: journal.keywords),
                    Self.jsonString(from: journal.insights),
                    journal.suggestedNextStep,
                    String(journal.moodScore),
                    journal.dominantEmotion,
                    journal.createdAt,
                ]
            )
        }
    }

    func upsertRemoteStateProfiles(_ profiles: [RemoteStateProfile]) {
        for profile in profiles {
            execute(
                sql: """
                INSERT OR REPLACE INTO user_state_profiles (
                    id, user_id, domain, stage, summary, intensity, trend, confidence,
                    evidence, support_strategy, source_session_id, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    profile.id,
                    profile.userID,
                    profile.domain,
                    profile.stage,
                    profile.summary,
                    String(profile.intensity),
                    profile.trend,
                    String(profile.confidence),
                    Self.jsonString(from: profile.evidence),
                    profile.supportStrategy,
                    profile.sourceSessionID,
                    profile.createdAt,
                    profile.updatedAt,
                ]
            )
        }
    }

    func messages(sessionID: String, limit: Int = 120) -> [ChatMessage] {
        rows(
            sql: """
            SELECT id, role, content, metadata, created_at
            FROM messages
            WHERE session_id = ?
            ORDER BY created_at ASC
            LIMIT ?
            """,
            bindings: [sessionID, String(limit)]
        )
        .map { Self.chatMessage(from: $0) }
    }

    func memories(limit: Int = 80) -> [MemoryEntry] {
        rows(
            sql: """
            SELECT id, category, subcategory, content, evidence, keywords, source_session_id, importance, updated_at
            FROM memories
            WHERE status = 'active'
            ORDER BY importance DESC, updated_at DESC
            LIMIT ?
            """,
            bindings: [String(limit)]
        )
        .map { row in
            MemoryEntry(
                id: row["id"] ?? UUID().uuidString,
                category: row["category"] ?? "memory",
                subcategory: row["subcategory"] ?? "general",
                content: row["content"] ?? "",
                evidence: row["evidence"] ?? "",
                keywords: Self.stringArray(from: row["keywords"] ?? "[]"),
                sourceSessionID: row["source_session_id"] ?? "",
                importance: Int(row["importance"] ?? "0") ?? 0,
                updatedAt: row["updated_at"] ?? ""
            )
        }
    }

    func journals(limit: Int = 20) -> [JournalEntry] {
        rows(
            sql: """
            SELECT id, session_id, summary, emotion_curve, keywords, insights, dominant_emotion, mood_score, suggested_next_step, created_at
            FROM journals
            ORDER BY created_at DESC
            LIMIT ?
            """,
            bindings: [String(limit)]
        )
        .map { row in
            JournalEntry(
                id: row["id"] ?? UUID().uuidString,
                sessionID: row["session_id"] ?? "",
                summary: row["summary"] ?? "",
                emotionCurve: Self.stringArray(from: row["emotion_curve"] ?? "[]"),
                keywords: Self.stringArray(from: row["keywords"] ?? "[]"),
                insights: Self.stringArray(from: row["insights"] ?? "[]"),
                dominantEmotion: row["dominant_emotion"] ?? "",
                moodScore: Int(row["mood_score"] ?? "0") ?? 0,
                suggestedNextStep: row["suggested_next_step"] ?? "",
                createdAt: row["created_at"] ?? ""
            )
        }
    }

    func stateProfiles(limit: Int = 40) -> [StateProfile] {
        rows(
            sql: """
            SELECT id, domain, stage, summary, intensity, trend, confidence, evidence, support_strategy, source_session_id, updated_at
            FROM user_state_profiles
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            bindings: [String(limit)]
        )
        .map { row in
            StateProfile(
                id: row["id"] ?? UUID().uuidString,
                domain: row["domain"] ?? "状态",
                stage: row["stage"] ?? "",
                summary: row["summary"] ?? "",
                intensity: Int(row["intensity"] ?? "0") ?? 0,
                trend: row["trend"] ?? "",
                confidence: Double(row["confidence"] ?? "0") ?? 0,
                evidence: row["evidence"] ?? "",
                supportStrategy: row["support_strategy"] ?? "",
                sourceSessionID: row["source_session_id"] ?? "",
                updatedAt: row["updated_at"] ?? ""
            )
        }
    }

    func latestStarMapInsight() -> StarMapInsight? {
        ensureStarMapInsightTable()
        return latestPersistedStarMapInsight()
    }

    func saveStarMapInsight(_ insight: StarMapInsight) {
        ensureStarMapInsightTable()
        persistStarMapInsight(insight)
    }

    private func ensureStarMapInsightTable() {
        execute(
            sql: """
            CREATE TABLE IF NOT EXISTS star_map_insights (
                id TEXT PRIMARY KEY,
                generated_at TEXT NOT NULL,
                period_start TEXT NOT NULL,
                period_end TEXT NOT NULL,
                core_insight TEXT NOT NULL,
                core_insight_detail TEXT NOT NULL DEFAULT '',
                recent_pattern_title TEXT NOT NULL,
                recent_pattern_items TEXT NOT NULL,
                recent_pattern_detail TEXT NOT NULL DEFAULT '',
                flow_condition_title TEXT NOT NULL,
                flow_condition_items TEXT NOT NULL,
                flow_condition_detail TEXT NOT NULL DEFAULT '',
                gentle_reminder_title TEXT NOT NULL DEFAULT '',
                gentle_reminder TEXT NOT NULL,
                gentle_reminder_detail TEXT NOT NULL DEFAULT '',
                source_summary TEXT NOT NULL
            )
            """
        )
        ensureColumn(
            table: "star_map_insights",
            column: "core_insight_detail",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        ensureColumn(
            table: "star_map_insights",
            column: "recent_pattern_detail",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        ensureColumn(
            table: "star_map_insights",
            column: "flow_condition_detail",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        ensureColumn(
            table: "star_map_insights",
            column: "gentle_reminder_title",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        ensureColumn(
            table: "star_map_insights",
            column: "gentle_reminder_detail",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
    }

    private func latestPersistedStarMapInsight() -> StarMapInsight? {
        rows(
            sql: """
            SELECT id, generated_at, period_start, period_end, core_insight,
                   core_insight_detail, recent_pattern_title, recent_pattern_items,
                   recent_pattern_detail, flow_condition_title, flow_condition_items,
                   flow_condition_detail, gentle_reminder_title, gentle_reminder,
                   gentle_reminder_detail, source_summary
            FROM star_map_insights
            ORDER BY generated_at DESC
            LIMIT 1
            """
        )
        .first
        .flatMap { Self.starMapInsight(from: $0) }
    }

    private func persistStarMapInsight(_ insight: StarMapInsight) {
        execute(
            sql: """
            INSERT OR REPLACE INTO star_map_insights (
                id, generated_at, period_start, period_end, core_insight,
                core_insight_detail, recent_pattern_title, recent_pattern_items,
                recent_pattern_detail, flow_condition_title, flow_condition_items,
                flow_condition_detail, gentle_reminder_title, gentle_reminder,
                gentle_reminder_detail, source_summary
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                insight.id,
                Self.string(from: insight.generatedAt),
                Self.string(from: insight.periodStart),
                Self.string(from: insight.periodEnd),
                insight.coreInsight,
                insight.coreInsightDetail,
                insight.recentPatternTitle,
                Self.jsonString(from: insight.recentPatternItems),
                insight.recentPatternDetail,
                insight.flowConditionTitle,
                Self.jsonString(from: insight.flowConditionItems),
                insight.flowConditionDetail,
                insight.gentleReminderTitle,
                insight.gentleReminder,
                insight.gentleReminderDetail,
                insight.sourceSummary,
            ]
        )
    }

    private func ensureColumn(table: String, column: String, definition: String) {
        let existingColumns = rows(sql: "PRAGMA table_info(\(table))").compactMap { $0["name"] }
        guard !existingColumns.contains(column) else { return }
        _ = execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private func rows(sql: String, bindings: [String] = []) -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        var result: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for columnIndex in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, columnIndex))
                if let text = sqlite3_column_text(statement, columnIndex) {
                    row[name] = String(cString: text)
                } else {
                    row[name] = ""
                }
            }
            result.append(row)
        }
        return result
    }

    @discardableResult
    private func execute(sql: String, bindings: [String] = []) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        return sqlite3_step(statement) == SQLITE_DONE
    }

    private static func preparedDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let writableURL = documentsURL.appendingPathComponent("app.db")
        guard let bundledURL = Bundle.main.url(forResource: "app", withExtension: "db") else {
            throw DatabaseError.missingBundledDatabase
        }

        if fileManager.fileExists(atPath: writableURL.path) {
            if shouldRefreshWritableDatabase(writableURL: writableURL, bundledURL: bundledURL) {
                try replaceWritableDatabase(at: writableURL, with: bundledURL, fileManager: fileManager)
            }
            return writableURL
        }

        try fileManager.copyItem(at: bundledURL, to: writableURL)
        return writableURL
    }

    private static func shouldRefreshWritableDatabase(writableURL: URL, bundledURL: URL) -> Bool {
        guard let bundledTimestamp = latestStoredTimestamp(at: bundledURL) else {
            return false
        }
        guard let writableTimestamp = latestStoredTimestamp(at: writableURL) else {
            return true
        }
        return bundledTimestamp > writableTimestamp
    }

    private static func replaceWritableDatabase(at writableURL: URL, with bundledURL: URL, fileManager: FileManager) throws {
        let temporaryURL = writableURL.deletingLastPathComponent().appendingPathComponent("app.db.next")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try fileManager.copyItem(at: bundledURL, to: temporaryURL)
        try fileManager.removeItem(at: writableURL)
        try fileManager.moveItem(at: temporaryURL, to: writableURL)
    }

    private static func latestStoredTimestamp(at databaseURL: URL) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }

        return scalarString(
            database: database,
            sql: """
            SELECT MAX(value) AS latest
            FROM (
                SELECT MAX(created_at) AS value FROM sessions
                UNION ALL SELECT MAX(created_at) FROM messages
                UNION ALL SELECT MAX(updated_at) FROM memories
                UNION ALL SELECT MAX(created_at) FROM journals
            )
            """
        )
    }

    private static func scalarString(database: OpaquePointer?, sql: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        let value = String(cString: text)
        return value.isEmpty ? nil : value
    }

    private static func metadataObject(from jsonString: String) -> [String: Any] {
        guard
            let data = jsonString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    private static func knowledgeCards(from value: Any?) -> [KnowledgeCard] {
        guard let ids = value as? [String] else { return [] }
        return ids.map { KnowledgeCard(id: $0, title: $0, concept: "") }
    }

    private static func stringArray(from jsonString: String) -> [String] {
        guard
            let data = jsonString.data(using: .utf8),
            let values = try? JSONSerialization.jsonObject(with: data) as? [String]
        else {
            return []
        }
        return values
    }

    private static func jsonString(from values: [String]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: values),
            let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    private static func metadataString(from message: RemoteChatMessage) -> String {
        var metadata: [String: Any] = [:]
        if !message.characterID.isEmpty {
            metadata["character_id"] = message.characterID
        }
        if !message.groupRole.isEmpty {
            metadata["group_role"] = message.groupRole
        }
        if !message.action.isEmpty {
            metadata["action"] = message.action
        }
        if !message.expressionID.isEmpty {
            metadata["expression_id"] = message.expressionID
        }
        if !message.knowledgeCardIDs.isEmpty {
            metadata["knowledge_card_ids"] = message.knowledgeCardIDs
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: metadata),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private static func starMapInsight(from row: [String: String]) -> StarMapInsight? {
        guard
            let generatedAt = date(from: row["generated_at"] ?? ""),
            let periodStart = date(from: row["period_start"] ?? ""),
            let periodEnd = date(from: row["period_end"] ?? "")
        else {
            return nil
        }
        return StarMapInsight(
            id: row["id"] ?? UUID().uuidString,
            generatedAt: generatedAt,
            periodStart: periodStart,
            periodEnd: periodEnd,
            coreInsight: row["core_insight"] ?? StarMapInsight.mock.coreInsight,
            coreInsightDetail: row["core_insight_detail"] ?? StarMapInsight.mock.coreInsightDetail,
            recentPatternTitle: row["recent_pattern_title"] ?? StarMapInsight.mock.recentPatternTitle,
            recentPatternItems: stringArray(from: row["recent_pattern_items"] ?? "[]"),
            recentPatternDetail: row["recent_pattern_detail"] ?? StarMapInsight.mock.recentPatternDetail,
            flowConditionTitle: row["flow_condition_title"] ?? StarMapInsight.mock.flowConditionTitle,
            flowConditionItems: stringArray(from: row["flow_condition_items"] ?? "[]"),
            flowConditionDetail: row["flow_condition_detail"] ?? StarMapInsight.mock.flowConditionDetail,
            gentleReminderTitle: row["gentle_reminder_title"] ?? StarMapInsight.mock.gentleReminderTitle,
            gentleReminder: row["gentle_reminder"] ?? StarMapInsight.mock.gentleReminder,
            gentleReminderDetail: row["gentle_reminder_detail"] ?? StarMapInsight.mock.gentleReminderDetail,
            sourceSummary: row["source_summary"] ?? ""
        )
    }

    private static func string(from date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    private static func date(from string: String) -> Date? {
        isoDateFormatter.date(from: string)
    }

    private static func chatMessage(from row: [String: String]) -> ChatMessage {
        let metadata = metadataObject(from: row["metadata"] ?? "{}")
        return ChatMessage(
            id: row["id"] ?? UUID().uuidString,
            role: MessageRole(rawValue: row["role"] ?? "") ?? .assistant,
            content: row["content"] ?? "",
            characterID: metadata["character_id"] as? String,
            createdAt: row["created_at"] ?? "",
            groupRole: metadata["group_role"] as? String ?? "",
            action: metadata["action"] as? String ?? "",
            expressionID: metadata["expression_id"] as? String ?? "",
            routeSummary: routeSummary(from: metadata["route_plan"] as? [String: Any]),
            knowledgeCards: knowledgeCards(from: metadata["knowledge_card_ids"])
        )
    }

    private static func routeSummary(from plan: [String: Any]?) -> String? {
        guard
            let plan
        else {
            return nil
        }
        if let characterID = plan["character_id"] as? String {
            let character = CompanionFixtures.character(id: characterID)
            let name = character?.name ?? "森森兔"
            let expressionID = plan["expression_id"] as? String ?? character?.defaultExpressionID ?? ""
            let expressionLabel = character?.expression(id: expressionID)?.label ?? expressionID
            let mode = (plan["response_mode"] as? String).flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
            if let reason = plan["reason"] as? String, !reason.isEmpty {
                return "本轮规划\(mode)：\(name) · \(expressionLabel)；\(reason)"
            }
            return "本轮规划\(mode)：\(name) · \(expressionLabel)"
        }
        guard
            let main = plan["main"] as? [String: Any],
            let mainID = main["character_id"] as? String
        else {
            return nil
        }
        let empathy = (plan["empathy"] as? [String: Any]) ?? (plan["empathic"] as? [String: Any])
        let need = (plan["need"] as? [String: Any]) ?? (plan["pinpoint"] as? [String: Any])
        let anchor = plan["anchor"] as? [String: Any]
        let empathyID = empathy?["character_id"] as? String
        let needID = need?["character_id"] as? String
        let empathyName = CompanionFixtures.character(id: empathyID)?.name ?? "一只小动物"
        let needName = CompanionFixtures.character(id: needID)?.name ?? "另一只小动物"
        let mainName = CompanionFixtures.character(id: mainID)?.name ?? "主回应"
        let anchorName = (anchor?["character_id"] as? String).flatMap { id in CompanionFixtures.character(id: id)?.name }
        let responseMode = plan["response_mode"] as? String
        let mode = responseMode.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
        if let anchorName {
            return "本轮规划\(mode)：\(empathyName)共情，\(needName)点明需求，\(mainName)主回复，\(anchorName)收束"
        }
        return "本轮规划\(mode)：\(empathyName)共情，\(needName)点明需求，\(mainName)主回复"
    }

    private static let isoDateFormatter = ISO8601DateFormatter()
    private static let allowedTables = Set(["sessions", "messages", "memories", "journals"])
}

enum DatabaseError: Error {
    case missingBundledDatabase
    case openFailed(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
