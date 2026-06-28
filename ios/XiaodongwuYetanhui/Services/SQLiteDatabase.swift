import Foundation
import SQLite3

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init() throws {
        let databaseURL = try Self.preparedDatabaseURL()
        if sqlite3_open(databaseURL.path, &handle) != SQLITE_OK {
            throw DatabaseError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        migrateLocalSchema()
    }

    deinit {
        sqlite3_close(handle)
    }

    private func migrateLocalSchema() {
        execute(
            sql: """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                ended_at TEXT
            )
            """
        )
        execute(
            sql: """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                model TEXT,
                metadata TEXT NOT NULL DEFAULT '{}',
                created_at TEXT NOT NULL
            )
            """
        )
        execute(
            sql: """
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL DEFAULT 'default',
                category TEXT NOT NULL,
                subcategory TEXT NOT NULL DEFAULT 'general',
                keywords TEXT NOT NULL DEFAULT '[]',
                status TEXT NOT NULL DEFAULT 'active',
                content TEXT NOT NULL,
                evidence TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 0.5,
                importance INTEGER NOT NULL DEFAULT 1,
                source_session_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        execute(
            sql: """
            CREATE TABLE IF NOT EXISTS journals (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                summary TEXT NOT NULL,
                emotion_curve TEXT NOT NULL DEFAULT '[]',
                keywords TEXT NOT NULL DEFAULT '[]',
                insights TEXT NOT NULL DEFAULT '[]',
                suggested_next_step TEXT NOT NULL DEFAULT '',
                mood_score INTEGER,
                dominant_emotion TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL
            )
            """
        )
        execute(
            sql: """
            CREATE TABLE IF NOT EXISTS user_state_profiles (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL DEFAULT 'default',
                domain TEXT NOT NULL,
                stage TEXT NOT NULL DEFAULT '',
                summary TEXT NOT NULL DEFAULT '',
                intensity INTEGER NOT NULL DEFAULT 0,
                trend TEXT NOT NULL DEFAULT '',
                confidence REAL NOT NULL DEFAULT 0,
                evidence TEXT NOT NULL DEFAULT '[]',
                support_strategy TEXT NOT NULL DEFAULT '',
                source_session_id TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(user_id, domain)
            )
            """
        )
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

    func createLocalSession() -> String {
        let sessionID = UUID().uuidString
        execute(
            sql: "INSERT INTO sessions (id, created_at) VALUES (?, ?)",
            bindings: [sessionID, Self.string(from: Date())]
        )
        return sessionID
    }

    func endLocalSession(_ sessionID: String) {
        execute(
            sql: "UPDATE sessions SET ended_at = ? WHERE id = ?",
            bindings: [Self.string(from: Date()), sessionID]
        )
    }

    func addLocalJournal(sessionID: String, journal: LocalJournalDraft) {
        execute(
            sql: """
            INSERT INTO journals (
                id, session_id, summary, emotion_curve, keywords, insights,
                suggested_next_step, mood_score, dominant_emotion, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                UUID().uuidString,
                sessionID,
                journal.summary,
                Self.jsonString(from: journal.emotionCurve),
                Self.jsonString(from: journal.keywords),
                Self.jsonString(from: journal.insights),
                journal.suggestedNextStep,
                String(journal.moodScore),
                journal.dominantEmotion,
                Self.string(from: Date()),
            ]
        )
    }

    func addLocalMemories(sessionID: String, memories: [LocalMemoryDraft]) {
        let now = Self.string(from: Date())
        for memory in memories {
            execute(
                sql: """
                INSERT INTO memories (
                    id, user_id, category, subcategory, keywords, status, content,
                    evidence, confidence, importance, source_session_id, created_at, updated_at
                )
                VALUES (?, 'default', ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    UUID().uuidString,
                    memory.category,
                    memory.subcategory,
                    Self.jsonString(from: memory.keywords),
                    memory.content,
                    memory.evidence,
                    String(memory.confidence),
                    String(memory.importance),
                    sessionID,
                    now,
                    now,
                ]
            )
        }
    }

    func upsertLocalStateProfiles(sessionID: String, profiles: [LocalStateProfileDraft]) {
        let now = Self.string(from: Date())
        for profile in profiles {
            guard profile.action != "no_change" else { continue }
            let existing = rows(
                sql: """
                SELECT evidence
                FROM user_state_profiles
                WHERE user_id = 'default' AND domain = ?
                LIMIT 1
                """,
                bindings: [profile.domain]
            ).first
            var evidence = Self.stringArray(from: existing?["evidence"] ?? "[]")
            for item in profile.evidence where !item.isEmpty && !evidence.contains(item) {
                evidence.append(item)
            }
            evidence = Array(evidence.suffix(8))
            execute(
                sql: """
                INSERT INTO user_state_profiles (
                    id, user_id, domain, stage, summary, intensity, trend, confidence,
                    evidence, support_strategy, source_session_id, created_at, updated_at
                )
                VALUES (?, 'default', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(user_id, domain) DO UPDATE SET
                    stage = excluded.stage,
                    summary = excluded.summary,
                    intensity = excluded.intensity,
                    trend = excluded.trend,
                    confidence = excluded.confidence,
                    evidence = excluded.evidence,
                    support_strategy = excluded.support_strategy,
                    source_session_id = excluded.source_session_id,
                    updated_at = excluded.updated_at
                """,
                bindings: [
                    UUID().uuidString,
                    profile.domain,
                    profile.stage,
                    profile.summary,
                    String(profile.intensity),
                    profile.trend,
                    String(profile.confidence),
                    Self.jsonString(from: evidence),
                    profile.supportStrategy,
                    sessionID,
                    now,
                    now,
                ]
            )
        }
    }

    @discardableResult
    func addLocalMessage(
        sessionID: String,
        role: MessageRole,
        content: String,
        characterID: String? = nil,
        expressionID: String = "",
        model: String = "",
        routePlan: [String: Any]? = nil,
        knowledgeCards: [KnowledgeCard] = []
    ) -> ChatMessage {
        let messageID = UUID().uuidString
        let createdAt = Self.string(from: Date())
        var metadata: [String: Any] = [:]
        if let characterID, !characterID.isEmpty {
            metadata["character_id"] = characterID
        }
        if !expressionID.isEmpty {
            metadata["expression_id"] = expressionID
        }
        if let routePlan {
            metadata["route_plan"] = routePlan
        }
        if !knowledgeCards.isEmpty {
            metadata["knowledge_card_ids"] = knowledgeCards.map(\.id)
        }
        execute(
            sql: """
            INSERT INTO messages (id, session_id, role, content, model, metadata, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                messageID,
                sessionID,
                role.rawValue,
                content,
                model,
                Self.jsonString(from: metadata),
                createdAt,
            ]
        )
        return ChatMessage(
            id: messageID,
            role: role,
            content: content,
            characterID: characterID,
            createdAt: createdAt,
            expressionID: expressionID,
            routeSummary: Self.routeSummary(from: routePlan),
            knowledgeCards: knowledgeCards
        )
    }

    func contextMemories(queryTerms: [String], limit: Int = 8) -> [MemoryEntry] {
        let all = memories(limit: 120)
        let terms = queryTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        var scoredMemories: [(memory: MemoryEntry, score: Int)] = []
        for memory in all {
            let textParts = [memory.content, memory.evidence] + memory.keywords
            let searchableText = textParts.joined(separator: " ").lowercased()
            var score = 0
            for term in terms {
                if searchableText.contains(term) {
                    score += 4
                } else if memory.keywords.contains(where: { term.contains($0.lowercased()) }) {
                    score += 1
                }
            }
            scoredMemories.append((memory: memory, score: score))
        }
        let related = scoredMemories
            .filter { $0.1 > 0 }
            .sorted {
                $0.1 == $1.1 ? $0.0.importance > $1.0.importance : $0.1 > $1.1
            }
            .map(\.0)
        let recent = all.sorted { $0.updatedAt > $1.updatedAt }
        let important = all.sorted {
            $0.importance == $1.importance ? $0.updatedAt > $1.updatedAt : $0.importance > $1.importance
        }
        var selected: [MemoryEntry] = []
        for memory in Array(related.prefix(5)) + Array(recent.prefix(2)) + Array(important.prefix(2)) {
            if !selected.contains(where: { $0.id == memory.id }) {
                selected.append(memory)
            }
            if selected.count == limit {
                break
            }
        }
        return selected
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

    func makeSyncUploadBundle() -> SyncUploadBundle {
        let sessionRecords = rows(
            sql: "SELECT id, created_at, ended_at FROM sessions ORDER BY created_at ASC"
        ).compactMap { row -> SyncSessionRecord? in
            guard let id = row["id"], let createdAt = row["created_at"] else { return nil }
            let endedAt = row["ended_at"].flatMap { $0.isEmpty ? nil : $0 }
            return SyncSessionRecord(id: id, createdAt: createdAt, endedAt: endedAt)
        }

        let messageRecords = rows(
            sql: """
            SELECT id, session_id, role, content, model, metadata, created_at
            FROM messages
            ORDER BY created_at ASC
            """
        ).compactMap { row -> SyncMessageRecord? in
            guard
                let id = row["id"],
                let sessionID = row["session_id"],
                let createdAt = row["created_at"]
            else {
                return nil
            }
            let metadata = Self.metadataObject(from: row["metadata"] ?? "{}")
            return SyncMessageRecord(
                id: id,
                sessionID: sessionID,
                role: row["role"] ?? "assistant",
                content: row["content"] ?? "",
                model: row["model"].flatMap { $0.isEmpty ? nil : $0 },
                metadata: SyncMessageMetadata(
                    characterID: metadata["character_id"] as? String,
                    groupRole: metadata["group_role"] as? String,
                    action: metadata["action"] as? String,
                    expressionID: metadata["expression_id"] as? String,
                    knowledgeCardIDs: metadata["knowledge_card_ids"] as? [String] ?? [],
                    routePlan: SyncRoutePlanRecord(
                        dictionary: metadata["route_plan"] as? [String: Any]
                    )
                ),
                createdAt: createdAt
            )
        }

        let memoryRecords = rows(
            sql: """
            SELECT id, user_id, category, subcategory, keywords, status, content,
                   evidence, confidence, importance, source_session_id, created_at, updated_at
            FROM memories
            """
        ).compactMap { row -> SyncMemoryRecord? in
            guard
                let id = row["id"],
                let createdAt = row["created_at"],
                let updatedAt = row["updated_at"]
            else {
                return nil
            }
            return SyncMemoryRecord(
                id: id,
                userID: row["user_id"] ?? "default",
                category: row["category"] ?? "memory",
                subcategory: row["subcategory"] ?? "general",
                keywords: Self.stringArray(from: row["keywords"] ?? "[]"),
                status: row["status"] ?? "active",
                content: row["content"] ?? "",
                evidence: row["evidence"] ?? "",
                confidence: Double(row["confidence"] ?? "0.5") ?? 0.5,
                importance: Int(row["importance"] ?? "1") ?? 1,
                sourceSessionID: row["source_session_id"] ?? "",
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        let journalRecords = rows(
            sql: """
            SELECT id, session_id, summary, emotion_curve, keywords, insights,
                   suggested_next_step, mood_score, dominant_emotion, created_at
            FROM journals
            """
        ).compactMap { row -> SyncJournalRecord? in
            guard
                let id = row["id"],
                let sessionID = row["session_id"],
                let createdAt = row["created_at"]
            else {
                return nil
            }
            return SyncJournalRecord(
                id: id,
                sessionID: sessionID,
                summary: row["summary"] ?? "",
                emotionCurve: Self.stringArray(from: row["emotion_curve"] ?? "[]"),
                keywords: Self.stringArray(from: row["keywords"] ?? "[]"),
                insights: Self.stringArray(from: row["insights"] ?? "[]"),
                suggestedNextStep: row["suggested_next_step"] ?? "",
                moodScore: Int(row["mood_score"] ?? ""),
                dominantEmotion: row["dominant_emotion"] ?? "",
                createdAt: createdAt
            )
        }

        let profileRecords = rows(
            sql: """
            SELECT id, user_id, domain, stage, summary, intensity, trend, confidence,
                   evidence, support_strategy, source_session_id, created_at, updated_at
            FROM user_state_profiles
            """
        ).compactMap { row -> SyncStateProfileRecord? in
            guard
                let id = row["id"],
                let domain = row["domain"],
                let createdAt = row["created_at"],
                let updatedAt = row["updated_at"]
            else {
                return nil
            }
            return SyncStateProfileRecord(
                id: id,
                userID: row["user_id"] ?? "default",
                domain: domain,
                stage: row["stage"] ?? "",
                summary: row["summary"] ?? "",
                intensity: Int(row["intensity"] ?? "0") ?? 0,
                trend: row["trend"] ?? "",
                confidence: Double(row["confidence"] ?? "0") ?? 0,
                evidence: Self.stringArray(from: row["evidence"] ?? "[]"),
                supportStrategy: row["support_strategy"] ?? "",
                sourceSessionID: row["source_session_id"] ?? "",
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        return SyncUploadBundle(
            sessions: sessionRecords,
            messages: messageRecords,
            memories: memoryRecords,
            journals: journalRecords,
            stateProfiles: profileRecords
        )
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
                primary_goal_title TEXT NOT NULL DEFAULT '',
                primary_goal_reason TEXT NOT NULL DEFAULT '',
                primary_goal_next_step TEXT NOT NULL DEFAULT '',
                primary_goal_challenge TEXT NOT NULL DEFAULT '',
                secondary_goal_title TEXT NOT NULL DEFAULT '',
                secondary_goal_reason TEXT NOT NULL DEFAULT '',
                secondary_goal_next_step TEXT NOT NULL DEFAULT '',
                secondary_goal_challenge TEXT NOT NULL DEFAULT '',
                recent_emotion_summary TEXT NOT NULL DEFAULT '',
                recent_emotion_tags TEXT NOT NULL DEFAULT '[]',
                flow_support TEXT NOT NULL DEFAULT '',
                memory_cues TEXT NOT NULL DEFAULT '[]',
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
        ensureColumn(table: "star_map_insights", column: "primary_goal_title", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "primary_goal_reason", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "primary_goal_next_step", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "primary_goal_challenge", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "secondary_goal_title", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "secondary_goal_reason", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "secondary_goal_next_step", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "secondary_goal_challenge", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "recent_emotion_summary", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "recent_emotion_tags", definition: "TEXT NOT NULL DEFAULT '[]'")
        ensureColumn(table: "star_map_insights", column: "flow_support", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(table: "star_map_insights", column: "memory_cues", definition: "TEXT NOT NULL DEFAULT '[]'")
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
            SELECT id, generated_at, period_start, period_end,
                   primary_goal_title, primary_goal_reason, primary_goal_next_step,
                   primary_goal_challenge, secondary_goal_title, secondary_goal_reason,
                   secondary_goal_next_step, secondary_goal_challenge,
                   recent_emotion_summary, recent_emotion_tags, flow_support, memory_cues,
                   core_insight,
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
                id, generated_at, period_start, period_end,
                primary_goal_title, primary_goal_reason, primary_goal_next_step,
                primary_goal_challenge, secondary_goal_title, secondary_goal_reason,
                secondary_goal_next_step, secondary_goal_challenge,
                recent_emotion_summary, recent_emotion_tags, flow_support, memory_cues,
                core_insight,
                core_insight_detail, recent_pattern_title, recent_pattern_items,
                recent_pattern_detail, flow_condition_title, flow_condition_items,
                flow_condition_detail, gentle_reminder_title, gentle_reminder,
                gentle_reminder_detail, source_summary
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                insight.id,
                Self.string(from: insight.generatedAt),
                Self.string(from: insight.periodStart),
                Self.string(from: insight.periodEnd),
                insight.primaryGoalTitle,
                insight.primaryGoalReason,
                insight.primaryGoalNextStep,
                insight.primaryGoalChallenge,
                insight.secondaryGoalTitle,
                insight.secondaryGoalReason,
                insight.secondaryGoalNextStep,
                insight.secondaryGoalChallenge,
                insight.recentEmotionSummary,
                Self.jsonString(from: insight.recentEmotionTags),
                insight.flowSupport,
                Self.jsonString(from: insight.memoryCues),
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

        if fileManager.fileExists(atPath: writableURL.path) {
            return writableURL
        }

        if let bundledURL = Bundle.main.url(forResource: "app", withExtension: "db") {
            try fileManager.copyItem(at: bundledURL, to: writableURL)
        } else {
            fileManager.createFile(atPath: writableURL.path, contents: nil)
        }
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

    private static func jsonString(from object: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
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
        if let routePlan = message.routePlan {
            metadata["route_plan"] = routePlan.dictionary
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
            primaryGoalTitle: row["primary_goal_title"].flatMap { $0.isEmpty ? nil : $0 } ?? StarMapInsight.mock.primaryGoalTitle,
            primaryGoalReason: row["primary_goal_reason"].flatMap { $0.isEmpty ? nil : $0 } ?? StarMapInsight.mock.primaryGoalReason,
            primaryGoalNextStep: row["primary_goal_next_step"].flatMap { $0.isEmpty ? nil : $0 } ?? StarMapInsight.mock.primaryGoalNextStep,
            primaryGoalChallenge: row["primary_goal_challenge"].flatMap { $0.isEmpty ? nil : $0 } ?? StarMapInsight.mock.primaryGoalChallenge,
            secondaryGoalTitle: row["secondary_goal_title"] ?? "",
            secondaryGoalReason: row["secondary_goal_reason"] ?? "",
            secondaryGoalNextStep: row["secondary_goal_next_step"] ?? "",
            secondaryGoalChallenge: row["secondary_goal_challenge"] ?? "",
            recentEmotionSummary: row["recent_emotion_summary"].flatMap { $0.isEmpty ? nil : $0 } ?? StarMapInsight.mock.recentEmotionSummary,
            recentEmotionTags: stringArray(from: row["recent_emotion_tags"] ?? "[]"),
            flowSupport: row["flow_support"].flatMap { $0.isEmpty ? nil : $0 } ?? StarMapInsight.mock.flowSupport,
            memoryCues: stringArray(from: row["memory_cues"] ?? "[]"),
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
