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
                routeSummary: Self.routeSummary(from: metadata["route_plan"] as? [String: Any]),
                knowledgeCards: Self.knowledgeCards(from: metadata["knowledge_card_ids"])
            )
        }
    }

    func memories(limit: Int = 80) -> [MemoryEntry] {
        rows(
            sql: """
            SELECT id, category, subcategory, content, evidence, importance, updated_at
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
                importance: Int(row["importance"] ?? "0") ?? 0,
                updatedAt: row["updated_at"] ?? ""
            )
        }
    }

    func journals(limit: Int = 20) -> [JournalEntry] {
        rows(
            sql: """
            SELECT id, summary, dominant_emotion, mood_score, suggested_next_step, created_at
            FROM journals
            ORDER BY created_at DESC
            LIMIT ?
            """,
            bindings: [String(limit)]
        )
        .map { row in
            JournalEntry(
                id: row["id"] ?? UUID().uuidString,
                summary: row["summary"] ?? "",
                dominantEmotion: row["dominant_emotion"] ?? "",
                moodScore: Int(row["mood_score"] ?? "0") ?? 0,
                suggestedNextStep: row["suggested_next_step"] ?? "",
                createdAt: row["created_at"] ?? ""
            )
        }
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

    private static func preparedDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let writableURL = documentsURL.appendingPathComponent("app.db")
        if fileManager.fileExists(atPath: writableURL.path) {
            return writableURL
        }
        guard let bundledURL = Bundle.main.url(forResource: "app", withExtension: "db") else {
            throw DatabaseError.missingBundledDatabase
        }
        try fileManager.copyItem(at: bundledURL, to: writableURL)
        return writableURL
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

    private static func routeSummary(from plan: [String: Any]?) -> String? {
        guard
            let plan,
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
        let empathyName = CompanionFixtures.characters.first { $0.id == empathyID }?.name ?? "一只小动物"
        let needName = CompanionFixtures.characters.first { $0.id == needID }?.name ?? "另一只小动物"
        let mainName = CompanionFixtures.characters.first { $0.id == mainID }?.name ?? "主回应"
        let anchorName = (anchor?["character_id"] as? String).flatMap { id in CompanionFixtures.characters.first { $0.id == id }?.name }
        let responseMode = plan["response_mode"] as? String
        let mode = responseMode.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
        if let anchorName {
            return "本轮规划\(mode)：\(empathyName)共情，\(needName)点明需求，\(mainName)主回复，\(anchorName)收束"
        }
        return "本轮规划\(mode)：\(empathyName)共情，\(needName)点明需求，\(mainName)主回复"
    }

    private static let allowedTables = Set(["sessions", "messages", "memories", "journals"])
}

enum DatabaseError: Error {
    case missingBundledDatabase
    case openFailed(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
