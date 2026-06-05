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
            ChatMessage(
                id: row["id"] ?? UUID().uuidString,
                role: MessageRole(rawValue: row["role"] ?? "") ?? .assistant,
                content: row["content"] ?? "",
                characterID: Self.characterID(from: row["metadata"] ?? "{}"),
                createdAt: row["created_at"] ?? ""
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

    private static func characterID(from jsonString: String) -> String? {
        guard
            let data = jsonString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["character_id"] as? String
    }

    private static let allowedTables = Set(["sessions", "messages", "memories", "journals"])
}

enum DatabaseError: Error {
    case missingBundledDatabase
    case openFailed(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
