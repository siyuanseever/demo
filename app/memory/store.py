import json
import logging
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any

from app.memory.schema import (
    MEMORY_SUBCATEGORIES,
    STATE_PROFILE_DOMAINS,
    normalize_memory_subcategory,
)


LOGGER = logging.getLogger(__name__)


POSITIVE_MOOD_WORDS = {
    "开心",
    "平静",
    "轻松",
    "稳定",
    "温暖",
    "被理解",
    "安心",
    "希望",
    "恢复",
    "清晰",
    "有力量",
    "放松",
}

NEGATIVE_MOOD_WORDS = {
    "焦虑",
    "痛苦",
    "崩溃",
    "冻结",
    "羞耻",
    "疲惫",
    "孤独",
    "害怕",
    "紧张",
    "无力",
    "混乱",
    "难过",
    "愤怒",
    "压抑",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return dict(row)


def message_row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    metadata_raw = item.pop("metadata", "{}") or "{}"
    try:
        metadata = json.loads(metadata_raw)
    except json.JSONDecodeError:
        metadata = {}
    item["metadata"] = metadata
    item["character_id"] = metadata.get("character_id", "")
    item["group_id"] = metadata.get("group_id", "")
    item["group_role"] = metadata.get("group_role", "")
    item["group_index"] = metadata.get("group_index")
    item["action"] = metadata.get("action", "")
    item["expression_id"] = metadata.get("expression_id", "")
    item["reply_path"] = metadata.get("reply_path", "")
    item["reply_stage"] = metadata.get("reply_stage", "")
    item["reply_group_id"] = metadata.get("reply_group_id", "")
    item["knowledge_card_ids"] = metadata.get("knowledge_card_ids", [])
    item["route_plan"] = metadata.get("route_plan")
    if not isinstance(item["knowledge_card_ids"], list):
        item["knowledge_card_ids"] = []
    return item


def parse_iso_datetime(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def mood_score_for_journal(journal: dict[str, Any]) -> int:
    text_parts = [
        journal.get("summary", ""),
        journal.get("suggested_next_step", ""),
        " ".join(journal.get("emotion_curve", [])),
        " ".join(journal.get("keywords", [])),
        " ".join(journal.get("insights", [])),
    ]
    text = " ".join(text_parts)
    score = 0
    for word in POSITIVE_MOOD_WORDS:
        if word in text:
            score += 1
    for word in NEGATIVE_MOOD_WORDS:
        if word in text:
            score -= 1
    return max(-3, min(3, score))


def tokenize_query(text: str) -> list[str]:
    normalized = text
    for char in "，。！？；：、,.!?;:\n\t":
        normalized = normalized.replace(char, " ")
    return [chunk.strip() for chunk in normalized.split() if chunk.strip()]


class Store:
    def __init__(self, path: str) -> None:
        self.path = path
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        self.migrate()

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def migrate(self) -> None:
        with self.connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    created_at TEXT NOT NULL,
                    ended_at TEXT
                );

                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    model TEXT,
                    metadata TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS memories (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    category TEXT NOT NULL,
                    content TEXT NOT NULL,
                    evidence TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    importance INTEGER NOT NULL,
                    source_session_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS journals (
                    id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    emotion_curve TEXT NOT NULL,
                    keywords TEXT NOT NULL,
                    insights TEXT NOT NULL,
                    suggested_next_step TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS user_state_profiles (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    domain TEXT NOT NULL,
                    stage TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    intensity INTEGER NOT NULL,
                    trend TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    evidence TEXT NOT NULL,
                    support_strategy TEXT NOT NULL,
                    source_session_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(user_id, domain)
                );

                CREATE TABLE IF NOT EXISTS user_state_profile_versions (
                    id TEXT PRIMARY KEY,
                    profile_id TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    domain TEXT NOT NULL,
                    stage TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    intensity INTEGER NOT NULL,
                    trend TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    evidence TEXT NOT NULL,
                    support_strategy TEXT NOT NULL,
                    source_session_id TEXT NOT NULL,
                    action TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS memory_events (
                    id TEXT PRIMARY KEY,
                    memory_id TEXT,
                    session_id TEXT NOT NULL,
                    action TEXT NOT NULL,
                    category TEXT NOT NULL,
                    subcategory TEXT NOT NULL,
                    content TEXT NOT NULL,
                    reason TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS home_hint_feedback (
                    id TEXT PRIMARY KEY,
                    hint_id TEXT NOT NULL UNIQUE,
                    text TEXT NOT NULL,
                    liked INTEGER NOT NULL,
                    source TEXT NOT NULL DEFAULT '',
                    context TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )
            self._ensure_column(conn, "memories", "subcategory", "TEXT NOT NULL DEFAULT 'general'")
            self._ensure_column(conn, "memories", "keywords", "TEXT NOT NULL DEFAULT '[]'")
            self._ensure_column(conn, "memories", "status", "TEXT NOT NULL DEFAULT 'active'")
            self._ensure_column(conn, "memories", "merged_into_id", "TEXT")
            self._ensure_column(conn, "memories", "merge_note", "TEXT NOT NULL DEFAULT ''")
            self._ensure_column(conn, "journals", "mood_score", "INTEGER")
            self._ensure_column(conn, "journals", "dominant_emotion", "TEXT NOT NULL DEFAULT ''")
            self._ensure_table(conn, "mental_status_records",
                """
                CREATE TABLE IF NOT EXISTS mental_status_records (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    record_date TEXT NOT NULL,
                    record_time TEXT,
                    source_type TEXT NOT NULL,
                    source_id TEXT,
                    mood TEXT,
                    mood_intensity INTEGER,
                    emotions TEXT NOT NULL DEFAULT '{}',
                    energy_level INTEGER,
                    sleep_quality INTEGER,
                    social_drive INTEGER,
                    focus_level INTEGER,
                    triggers TEXT,
                    coping TEXT,
                    notes TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(user_id, record_date, record_time)
                )
                """)
            self._ensure_table(conn, "user_document_sources",
                """
                CREATE TABLE IF NOT EXISTS user_document_sources (
                    id TEXT PRIMARY KEY,
                    source_type TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    file_hash TEXT NOT NULL,
                    extracted_memory_ids TEXT,
                    extracted_record_ids TEXT,
                    last_imported_at TEXT,
                    document_date TEXT,
                    UNIQUE(file_path)
                )
                """)

    def record_home_hint_feedback(
        self,
        *,
        hint_id: str,
        text: str,
        liked: bool,
        source: str = "",
        context: dict[str, Any] | None = None,
    ) -> None:
        now = utc_now()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO home_hint_feedback (
                    id, hint_id, text, liked, source, context, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(hint_id) DO UPDATE SET
                    text = excluded.text,
                    liked = excluded.liked,
                    source = excluded.source,
                    context = excluded.context,
                    updated_at = excluded.updated_at
                """,
                (
                    str(uuid.uuid4()),
                    hint_id,
                    text,
                    1 if liked else 0,
                    source,
                    json.dumps(context or {}, ensure_ascii=False),
                    now,
                    now,
                ),
            )

    def list_home_hint_feedback(
        self,
        *,
        liked: bool | None = None,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        with self.connect() as conn:
            if liked is None:
                cursor = conn.execute(
                    """
                    SELECT id, hint_id, text, liked, source, context, created_at, updated_at
                    FROM home_hint_feedback
                    ORDER BY updated_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT id, hint_id, text, liked, source, context, created_at, updated_at
                    FROM home_hint_feedback
                    WHERE liked = ?
                    ORDER BY updated_at DESC
                    LIMIT ?
                    """,
                    (1 if liked else 0, limit),
                )
        rows = [row_to_dict(row) for row in cursor.fetchall()]
        for row in rows:
            row["liked"] = bool(row.get("liked"))
            try:
                row["context"] = json.loads(row.get("context") or "{}")
            except (TypeError, json.JSONDecodeError):
                row["context"] = {}
        return rows

    def _ensure_column(
        self,
        conn: sqlite3.Connection,
        table: str,
        column: str,
        definition: str,
    ) -> None:
        import re as _re
        if not _re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', table):
            raise ValueError(f'Invalid table name: {table!r}')
        if not _re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', column):
            raise ValueError(f'Invalid column name: {column!r}')
        existing = {
            row["name"]
            for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
        }
        if column not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")

    def _ensure_table(
        self,
        conn: sqlite3.Connection,
        table: str,
        ddl: str,
    ) -> None:
        existing = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            (table,),
        ).fetchone()
        if not existing:
            conn.executescript(ddl)

    def create_session(self) -> str:
        session_id = str(uuid.uuid4())
        with self.connect() as conn:
            conn.execute(
                "INSERT INTO sessions (id, created_at) VALUES (?, ?)",
                (session_id, utc_now()),
            )
        return session_id

    def end_session(self, session_id: str) -> None:
        with self.connect() as conn:
            conn.execute(
                "UPDATE sessions SET ended_at = ? WHERE id = ?",
                (utc_now(), session_id),
            )

    def get_session(self, session_id: str) -> dict[str, Any] | None:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT id, created_at, ended_at FROM sessions WHERE id = ?",
                (session_id,),
            ).fetchone()
            return row_to_dict(row) if row else None

    def latest_message_at(self, session_id: str) -> str | None:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT MAX(created_at) AS latest_at FROM messages WHERE session_id = ?",
                (session_id,),
            ).fetchone()
            return row["latest_at"] if row else None

    def add_message(
        self,
        session_id: str,
        role: str,
        content: str,
        *,
        model: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> str:
        message_id = str(uuid.uuid4())
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO messages (id, session_id, role, content, model, metadata, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    message_id,
                    session_id,
                    role,
                    content,
                    model,
                    json.dumps(metadata or {}, ensure_ascii=False),
                    utc_now(),
                ),
            )
        return message_id

    def get_session_messages(self, session_id: str) -> list[sqlite3.Row]:
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT role, content, model, metadata, created_at
                FROM messages
                WHERE session_id = ?
                ORDER BY created_at ASC
                """,
                (session_id,),
            )
            return list(cursor.fetchall())

    def recent_memories(self, limit: int = 12) -> list[dict[str, Any]]:
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT
                    id, category, subcategory, keywords, content, evidence,
                    confidence, importance, status, updated_at
                FROM memories
                WHERE status = 'active'
                ORDER BY importance DESC, updated_at DESC
                LIMIT ?
                """,
                (limit,),
            )
            return [dict(row) for row in cursor.fetchall()]

    def add_memory(self, session_id: str, memory: dict[str, Any]) -> str:
        memory_id = str(uuid.uuid4())
        now = utc_now()
        subcategory = normalize_memory_subcategory(
            memory["category"],
            memory.get("subcategory"),
        )
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO memories (
                    id, user_id, category, subcategory, keywords, content, evidence,
                    confidence, importance, status, source_session_id, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    memory_id,
                    "default",
                    memory["category"],
                    subcategory,
                    json.dumps(memory.get("keywords", []), ensure_ascii=False),
                    memory["content"],
                    memory.get("evidence") or "",
                    float(memory.get("confidence", 0.5)),
                    int(memory.get("importance", 3)),
                    memory.get("status", "active"),
                    session_id,
                    now,
                    now,
                ),
            )
        return memory_id

    def add_memory_event(
        self,
        session_id: str,
        *,
        action: str,
        memory: dict[str, Any],
        memory_id: str | None = None,
        reason: str = "",
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO memory_events (
                    id, memory_id, session_id, action, category, subcategory,
                    content, reason, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    memory_id,
                    session_id,
                    action,
                    memory.get("category", ""),
                    memory.get("subcategory", "general"),
                    memory.get("content", ""),
                    reason,
                    utc_now(),
                ),
            )

    def add_memories(self, session_id: str, memories: list[dict[str, Any]]) -> None:
        for memory in memories[:3]:
            self.add_memory(session_id, memory)

    def update_memory(
        self,
        memory_id: str,
        updates: dict[str, Any],
        *,
        merge_note: str = "",
    ) -> None:
        normalized_updates = dict(updates)
        if "subcategory" in normalized_updates:
            category = str(normalized_updates.get("category") or "").strip()
            if not category:
                with self.connect() as conn:
                    row = conn.execute(
                        "SELECT category FROM memories WHERE id = ?",
                        (memory_id,),
                    ).fetchone()
                category = str(row["category"] if row else "")
            normalized_updates["subcategory"] = normalize_memory_subcategory(
                category,
                normalized_updates.get("subcategory"),
            )
        fields = []
        values = []
        for key in (
            "category",
            "subcategory",
            "content",
            "evidence",
            "confidence",
            "importance",
            "status",
        ):
            if key in normalized_updates:
                fields.append(f"{key} = ?")
                values.append(normalized_updates[key])
        if "keywords" in normalized_updates:
            fields.append("keywords = ?")
            values.append(json.dumps(normalized_updates["keywords"], ensure_ascii=False))
        if merge_note:
            fields.append("merge_note = ?")
            values.append(merge_note)
        fields.append("updated_at = ?")
        values.append(utc_now())
        values.append(memory_id)
        with self.connect() as conn:
            conn.execute(
                f"UPDATE memories SET {', '.join(fields)} WHERE id = ?",
                values,
            )

    def mark_memory(
        self,
        memory_id: str,
        *,
        status: str,
        merge_note: str = "",
        merged_into_id: str | None = None,
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE memories
                SET status = ?, merge_note = ?, merged_into_id = ?, updated_at = ?
                WHERE id = ?
                """,
                (status, merge_note, merged_into_id, utc_now(), memory_id),
            )

    def add_journal(self, session_id: str, journal: dict[str, Any]) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO journals (
                    id, session_id, summary, emotion_curve, keywords,
                    insights, suggested_next_step, mood_score, dominant_emotion, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    session_id,
                    journal.get("summary", ""),
                    json.dumps(journal.get("emotion_curve", []), ensure_ascii=False),
                    json.dumps(journal.get("keywords", []), ensure_ascii=False),
                    json.dumps(journal.get("insights", []), ensure_ascii=False),
                    journal.get("suggested_next_step", ""),
                    journal.get("mood_score"),
                    journal.get("dominant_emotion", ""),
                    utc_now(),
                ),
            )

    def list_state_profiles(self, limit: int = 100) -> list[dict[str, Any]]:
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT
                    id, user_id, domain, stage, summary, intensity, trend,
                    confidence, evidence, support_strategy, source_session_id,
                    created_at, updated_at
                FROM user_state_profiles
                ORDER BY domain ASC
                LIMIT ?
                """,
                (limit,),
            )
            profiles = [row_to_dict(row) for row in cursor.fetchall()]
        for profile in profiles:
            try:
                profile["evidence"] = json.loads(profile["evidence"])
            except (TypeError, json.JSONDecodeError):
                LOGGER.warning(
                    "invalid state profile evidence JSON profile_id=%s",
                    profile.get("id", ""),
                )
                profile["evidence"] = []
        return profiles

    def list_state_profile_versions(
        self,
        *,
        domain: str | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        with self.connect() as conn:
            if domain:
                cursor = conn.execute(
                    """
                    SELECT
                        id, profile_id, user_id, domain, stage, summary, intensity,
                        trend, confidence, evidence, support_strategy,
                        source_session_id, action, reason, created_at
                    FROM user_state_profile_versions
                    WHERE domain = ?
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (domain, limit),
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT
                        id, profile_id, user_id, domain, stage, summary, intensity,
                        trend, confidence, evidence, support_strategy,
                        source_session_id, action, reason, created_at
                    FROM user_state_profile_versions
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
            versions = [row_to_dict(row) for row in cursor.fetchall()]
        for version in versions:
            try:
                version["evidence"] = json.loads(version["evidence"])
            except (TypeError, json.JSONDecodeError):
                version["evidence"] = []
        return versions

    def state_profile_overview(self, *, versions_per_domain: int = 6) -> list[dict[str, Any]]:
        profiles = {profile["domain"]: profile for profile in self.list_state_profiles(limit=1000)}
        versions = self.list_state_profile_versions(limit=1000)
        versions_by_domain: dict[str, list[dict[str, Any]]] = {}
        for version in versions:
            versions_by_domain.setdefault(version["domain"], []).append(version)
        rows = []
        for domain in STATE_PROFILE_DOMAINS:
            rows.append(
                {
                    "domain": domain,
                    "current": profiles.get(domain),
                    "history": versions_by_domain.get(domain, [])[:versions_per_domain],
                }
            )
        for domain in sorted(set(profiles) - set(STATE_PROFILE_DOMAINS)):
            rows.append(
                {
                    "domain": domain,
                    "current": profiles.get(domain),
                    "history": versions_by_domain.get(domain, [])[:versions_per_domain],
                }
            )
        return rows

    def upsert_state_profile(
        self,
        session_id: str,
        profile: dict[str, Any],
        *,
        action: str,
        reason: str,
    ) -> dict[str, Any]:
        now = utc_now()
        user_id = "default"
        domain = profile["domain"]
        evidence = profile.get("evidence", [])
        if not isinstance(evidence, list):
            evidence = []
        values = {
            "stage": profile.get("stage", ""),
            "summary": profile.get("summary", ""),
            "intensity": int(profile.get("intensity", 5)),
            "trend": profile.get("trend", "unknown"),
            "confidence": float(profile.get("confidence", 0.5)),
            "evidence": json.dumps(evidence[:8], ensure_ascii=False),
            "support_strategy": profile.get("support_strategy", ""),
        }
        with self.connect() as conn:
            existing = conn.execute(
                """
                SELECT id, created_at
                FROM user_state_profiles
                WHERE user_id = ? AND domain = ?
                """,
                (user_id, domain),
            ).fetchone()
            if existing:
                profile_id = existing["id"]
                created_at = existing["created_at"]
                conn.execute(
                    """
                    UPDATE user_state_profiles
                    SET stage = ?, summary = ?, intensity = ?, trend = ?,
                        confidence = ?, evidence = ?, support_strategy = ?,
                        source_session_id = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        values["stage"],
                        values["summary"],
                        values["intensity"],
                        values["trend"],
                        values["confidence"],
                        values["evidence"],
                        values["support_strategy"],
                        session_id,
                        now,
                        profile_id,
                    ),
                )
            else:
                profile_id = str(uuid.uuid4())
                created_at = now
                conn.execute(
                    """
                    INSERT INTO user_state_profiles (
                        id, user_id, domain, stage, summary, intensity, trend,
                        confidence, evidence, support_strategy, source_session_id,
                        created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        profile_id,
                        user_id,
                        domain,
                        values["stage"],
                        values["summary"],
                        values["intensity"],
                        values["trend"],
                        values["confidence"],
                        values["evidence"],
                        values["support_strategy"],
                        session_id,
                        now,
                        now,
                    ),
                )
            version_id = str(uuid.uuid4())
            conn.execute(
                """
                INSERT INTO user_state_profile_versions (
                    id, profile_id, user_id, domain, stage, summary, intensity,
                    trend, confidence, evidence, support_strategy,
                    source_session_id, action, reason, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    version_id,
                    profile_id,
                    user_id,
                    domain,
                    values["stage"],
                    values["summary"],
                    values["intensity"],
                    values["trend"],
                    values["confidence"],
                    values["evidence"],
                    values["support_strategy"],
                    session_id,
                    action,
                    reason,
                    now,
                ),
            )
        return {
            "id": profile_id,
            "domain": domain,
            **values,
            "evidence": evidence[:8],
            "source_session_id": session_id,
            "created_at": created_at,
            "updated_at": now,
            "action": action,
            "reason": reason,
            "version_id": version_id,
        }

    def list_sessions(
        self,
        limit: int = 50,
        *,
        include_empty: bool = False,
    ) -> list[dict[str, Any]]:
        having = "" if include_empty else "HAVING message_count > 0 OR journal_count > 0"
        with self.connect() as conn:
            cursor = conn.execute(
                f"""
                SELECT
                    s.id,
                    s.created_at,
                    s.ended_at,
                    COUNT(DISTINCT m.id) AS message_count,
                    COUNT(DISTINCT j.id) AS journal_count
                FROM sessions s
                LEFT JOIN messages m ON m.session_id = s.id
                LEFT JOIN journals j ON j.session_id = s.id
                GROUP BY s.id
                {having}
                ORDER BY s.created_at DESC
                LIMIT ?
                """,
                (limit,),
            )
            return [row_to_dict(row) for row in cursor.fetchall()]

    def list_messages(
        self,
        *,
        session_id: str | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        with self.connect() as conn:
            if session_id:
                cursor = conn.execute(
                    """
                    SELECT id, session_id, role, content, model, metadata, created_at
                    FROM messages
                    WHERE session_id = ?
                    ORDER BY created_at ASC
                    LIMIT ?
                    """,
                    (session_id, limit),
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT id, session_id, role, content, model, metadata, created_at
                    FROM messages
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
            return [message_row_to_dict(row) for row in cursor.fetchall()]

    def list_memories(
        self,
        *,
        session_id: str | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        with self.connect() as conn:
            if session_id:
                cursor = conn.execute(
                    """
                    SELECT
                        id, user_id, category, subcategory, keywords, status,
                        content, evidence, confidence, importance, source_session_id,
                        merged_into_id, merge_note, created_at, updated_at
                    FROM memories
                    WHERE source_session_id = ?
                    ORDER BY importance DESC, updated_at DESC
                    LIMIT ?
                    """,
                    (session_id, limit),
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT
                        id, user_id, category, subcategory, keywords, status,
                        content, evidence, confidence, importance, source_session_id,
                        merged_into_id, merge_note, created_at, updated_at
                    FROM memories
                    ORDER BY category ASC, importance DESC, updated_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
            memories = [row_to_dict(row) for row in cursor.fetchall()]
        for memory in memories:
            memory["raw_subcategory"] = memory.get("subcategory", "")
            memory["subcategory"] = normalize_memory_subcategory(
                memory.get("category", ""),
                memory.get("subcategory"),
            )
            try:
                memory["keywords"] = json.loads(memory["keywords"])
            except (TypeError, json.JSONDecodeError):
                memory["keywords"] = []
        return memories

    def list_memory_events(
        self,
        *,
        session_id: str | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        with self.connect() as conn:
            if session_id:
                cursor = conn.execute(
                    """
                    SELECT id, memory_id, session_id, action, category, subcategory,
                           content, reason, created_at
                    FROM memory_events
                    WHERE session_id = ?
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (session_id, limit),
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT id, memory_id, session_id, action, category, subcategory,
                           content, reason, created_at
                    FROM memory_events
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
        return [row_to_dict(row) for row in cursor.fetchall()]

    def search_memories(
        self,
        query: str,
        *,
        query_terms: list[str] | None = None,
        limit: int = 8,
    ) -> list[dict[str, Any]]:
        tokens = []
        normalized_query = str(query or "").strip().lower()
        for token in tokenize_query(query):
            if token not in tokens:
                tokens.append(token)
        for term in query_terms or []:
            text = str(term or "").strip()
            if text and text not in tokens:
                tokens.append(text)
        if not tokens:
            return self.recent_memories(limit=limit)

        memories = [memory for memory in self.list_memories(limit=10000) if memory.get("status") == "active"]
        scored: list[tuple[float, dict[str, Any]]] = []
        for memory in memories:
            keywords = memory.get("keywords", [])
            if not isinstance(keywords, list):
                keywords = []
            normalized_keywords = [
                str(keyword or "").strip().lower()
                for keyword in keywords
                if str(keyword or "").strip()
            ]
            haystack = " ".join(
                [
                    memory.get("category", ""),
                    memory.get("subcategory", ""),
                    memory.get("content", ""),
                    memory.get("evidence", ""),
                    " ".join(str(keyword) for keyword in keywords),
                ]
            )
            score = 0.0
            for keyword in normalized_keywords:
                if keyword in normalized_query:
                    score += 5 + min(len(keyword), 6)
            for token in tokens:
                if not token:
                    continue
                normalized_token = token.lower()
                if normalized_token in normalized_keywords:
                    score += 4
                if normalized_token in memory.get("content", "").lower():
                    score += 3
                if normalized_token in memory.get("evidence", "").lower():
                    score += 2
                if normalized_token in haystack.lower():
                    score += 1
            if score > 0:
                score += float(memory.get("importance", 1)) * 0.2
                score += float(memory.get("confidence", 0.5)) * 0.2
                scored.append((score, memory))
        scored.sort(key=lambda item: item[0], reverse=True)
        return [memory for _, memory in scored[:limit]]

    def search_memories_hybrid(
        self,
        query: str,
        *,
        query_terms: list[str] | None = None,
        relevant_limit: int = 5,
        recent_limit: int = 1,
        important_limit: int = 2,
        important_threshold: int = 5,
        total_limit: int = 10,
    ) -> list[dict[str, Any]]:
        """相关检索优先；无相关结果时才回退到重要与近期记忆。

        Args:
            query: 用户输入文本。
            query_terms: 规划器输出的检索关键词。
            relevant_limit: 相关记忆层上限。
            recent_limit: 近期记忆层条数（按时间倒序）。
            important_limit: 重要记忆层条数上限。
            important_threshold: 重要性阈值，importance >= 此值视为重要。
            total_limit: 合并去重后总量上限。

        Returns:
            相关记忆，或无相关结果时的少量背景记忆。
        """
        seen_ids: set[str] = set()
        result: list[dict[str, Any]] = []

        def _dedup_append(memories_in: list[dict[str, Any]]) -> None:
            for memory in memories_in:
                memory_id = memory.get("id", "")
                if memory_id and memory_id not in seen_ids:
                    seen_ids.add(memory_id)
                    result.append(memory)

        # Layer 1: 相关记忆 — 使用 search_memories 的关键词匹配逻辑
        relevant = self.search_memories(
            query,
            query_terms=query_terms,
            limit=relevant_limit,
        )
        _dedup_append(relevant)
        if result:
            return result[:total_limit]

        # Fallback 1: 重要记忆 — 只在无相关结果时提供少量背景。
        important_rows = self.recent_memories(limit=200)
        important_memories = [
            dict(row) for row in important_rows
            if dict(row).get("importance", 0) >= important_threshold
        ]
        _dedup_append(important_memories[:important_limit])

        # Fallback 2: 近期记忆 — 避免在每个正常查询中固定注入同一批记忆。
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT id, category, subcategory, keywords, content, evidence,
                       confidence, importance, status, updated_at
                FROM memories
                WHERE status = 'active'
                ORDER BY updated_at DESC
                LIMIT ?
                """,
                (recent_limit + len(seen_ids),),
            )
            recent_rows = [dict(row) for row in cursor.fetchall()]
        recent_memories = [
            row for row in recent_rows if row.get("id", "") not in seen_ids
        ][:recent_limit]
        _dedup_append(recent_memories)

        return result[:total_limit]

    def memory_taxonomy_counts(self) -> list[dict[str, Any]]:
        memories = self.list_memories(limit=10000)
        counts: dict[tuple[str, str], int] = {}
        active_counts: dict[tuple[str, str], int] = {}
        for memory in memories:
            key = (memory["category"], memory.get("subcategory") or "general")
            counts[key] = counts.get(key, 0) + 1
            if memory.get("status") == "active":
                active_counts[key] = active_counts.get(key, 0) + 1

        rows = []
        for category, subcategories in MEMORY_SUBCATEGORIES.items():
            for subcategory in subcategories:
                key = (category, subcategory)
                rows.append(
                    {
                        "category": category,
                        "subcategory": subcategory,
                        "count": counts.get(key, 0),
                        "active_count": active_counts.get(key, 0),
                    }
                )

        unknown = sorted(
            key for key in counts if key[0] not in MEMORY_SUBCATEGORIES
            or key[1] not in MEMORY_SUBCATEGORIES.get(key[0], ())
        )
        for category, subcategory in unknown:
            rows.append(
                {
                    "category": category,
                    "subcategory": subcategory,
                    "count": counts[(category, subcategory)],
                    "active_count": active_counts.get((category, subcategory), 0),
                }
            )
        return rows

    def find_memory_candidates(
        self,
        memory: dict[str, Any],
        limit: int = 5,
    ) -> list[dict[str, Any]]:
        keywords = set(memory.get("keywords", []))
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT
                    id, category, subcategory, keywords, status, content, evidence,
                    confidence, importance, source_session_id, updated_at
                FROM memories
                WHERE status = 'active'
                  AND category = ?
                ORDER BY updated_at DESC
                LIMIT 200
                """,
                (memory["category"],),
            )
            candidates = [row_to_dict(row) for row in cursor.fetchall()]
        for candidate in candidates:
            candidate["subcategory"] = normalize_memory_subcategory(
                candidate.get("category", ""),
                candidate.get("subcategory"),
            )
            try:
                candidate["keywords"] = json.loads(candidate["keywords"])
            except (TypeError, json.JSONDecodeError):
                candidate["keywords"] = []
            overlap = keywords.intersection(candidate["keywords"])
            candidate["_score"] = (
                2 * int(
                    candidate["subcategory"]
                    == normalize_memory_subcategory(
                        memory.get("category", ""),
                        memory.get("subcategory"),
                    )
                )
                + len(overlap)
                + int(memory.get("content", "")[:12] in candidate["content"])
            )
        candidates.sort(
            key=lambda item: (item["_score"], item["importance"], item["updated_at"]),
            reverse=True,
        )
        return candidates[:limit]

    def list_journals(
        self,
        *,
        session_id: str | None = None,
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        with self.connect() as conn:
            if session_id:
                cursor = conn.execute(
                    """
                    SELECT
                        id, session_id, summary, emotion_curve, keywords,
                        insights, suggested_next_step, mood_score, dominant_emotion, created_at
                    FROM journals
                    WHERE session_id = ?
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (session_id, limit),
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT
                        id, session_id, summary, emotion_curve, keywords,
                        insights, suggested_next_step, mood_score, dominant_emotion, created_at
                    FROM journals
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
            journals = [row_to_dict(row) for row in cursor.fetchall()]
        for journal in journals:
            for key in ("emotion_curve", "keywords", "insights"):
                try:
                    journal[key] = json.loads(journal[key])
                except (TypeError, json.JSONDecodeError):
                    journal[key] = []
        return journals

    def delete_empty_sessions(self) -> int:
        with self.connect() as conn:
            cursor = conn.execute(
                """
                DELETE FROM sessions
                WHERE id NOT IN (SELECT DISTINCT session_id FROM messages)
                  AND id NOT IN (SELECT DISTINCT session_id FROM journals)
                """
            )
            return cursor.rowcount

    def merge_sync_bundle(self, payload: dict[str, Any]) -> dict[str, int]:
        counts = {
            "sessions": 0,
            "messages": 0,
            "memories": 0,
            "journals": 0,
            "state_profiles": 0,
        }
        with self.connect() as conn:
            for item in payload.get("sessions", []):
                if not item.get("id") or not item.get("created_at"):
                    continue
                conn.execute(
                    """
                    INSERT INTO sessions (id, created_at, ended_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        created_at = MIN(sessions.created_at, excluded.created_at),
                        ended_at = CASE
                            WHEN excluded.ended_at IS NOT NULL AND excluded.ended_at != ''
                            THEN excluded.ended_at
                            ELSE sessions.ended_at
                        END
                    """,
                    (item["id"], item["created_at"], item.get("ended_at") or None),
                )
                counts["sessions"] += 1

            for item in payload.get("messages", []):
                if not item.get("id") or not item.get("session_id"):
                    continue
                metadata = item.get("metadata", {})
                if not isinstance(metadata, dict):
                    metadata = {}
                cursor = conn.execute(
                    """
                    INSERT OR IGNORE INTO messages (
                        id, session_id, role, content, model, metadata, created_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        item["id"],
                        item["session_id"],
                        item.get("role", "assistant"),
                        item.get("content", ""),
                        item.get("model") or None,
                        json.dumps(metadata, ensure_ascii=False),
                        item.get("created_at") or utc_now(),
                    ),
                )
                counts["messages"] += max(cursor.rowcount, 0)

            for item in payload.get("memories", []):
                if not item.get("id") or not item.get("updated_at"):
                    continue
                cursor = conn.execute(
                    """
                    INSERT INTO memories (
                        id, user_id, category, subcategory, keywords, status,
                        content, evidence, confidence, importance, source_session_id,
                        created_at, updated_at
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
                        updated_at = excluded.updated_at
                    WHERE excluded.updated_at >= memories.updated_at
                    """,
                    (
                        item["id"],
                        item.get("user_id", "default"),
                        item.get("category", "memory"),
                        normalize_memory_subcategory(
                            item.get("category", ""),
                            item.get("subcategory"),
                        ),
                        json.dumps(item.get("keywords", []), ensure_ascii=False),
                        item.get("status", "active"),
                        item.get("content", ""),
                        item.get("evidence", ""),
                        float(item.get("confidence", 0.5)),
                        int(item.get("importance", 1)),
                        item.get("source_session_id", ""),
                        item.get("created_at") or item["updated_at"],
                        item["updated_at"],
                    ),
                )
                counts["memories"] += max(cursor.rowcount, 0)

            for item in payload.get("journals", []):
                if not item.get("id") or not item.get("session_id"):
                    continue
                cursor = conn.execute(
                    """
                    INSERT OR IGNORE INTO journals (
                        id, session_id, summary, emotion_curve, keywords, insights,
                        suggested_next_step, mood_score, dominant_emotion, created_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        item["id"],
                        item["session_id"],
                        item.get("summary", ""),
                        json.dumps(item.get("emotion_curve", []), ensure_ascii=False),
                        json.dumps(item.get("keywords", []), ensure_ascii=False),
                        json.dumps(item.get("insights", []), ensure_ascii=False),
                        item.get("suggested_next_step", ""),
                        item.get("mood_score"),
                        item.get("dominant_emotion", ""),
                        item.get("created_at") or utc_now(),
                    ),
                )
                counts["journals"] += max(cursor.rowcount, 0)

            for item in payload.get("state_profiles", []):
                if not item.get("id") or not item.get("domain") or not item.get("updated_at"):
                    continue
                existing = conn.execute(
                    """
                    SELECT updated_at
                    FROM user_state_profiles
                    WHERE user_id = ? AND domain = ?
                    """,
                    (item.get("user_id", "default"), item["domain"]),
                ).fetchone()
                if existing and existing["updated_at"] > item["updated_at"]:
                    continue
                conn.execute(
                    "DELETE FROM user_state_profiles WHERE user_id = ? AND domain = ?",
                    (item.get("user_id", "default"), item["domain"]),
                )
                conn.execute(
                    """
                    INSERT INTO user_state_profiles (
                        id, user_id, domain, stage, summary, intensity, trend,
                        confidence, evidence, support_strategy, source_session_id,
                        created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        item["id"],
                        item.get("user_id", "default"),
                        item["domain"],
                        item.get("stage", ""),
                        item.get("summary", ""),
                        int(item.get("intensity", 0)),
                        item.get("trend", ""),
                        float(item.get("confidence", 0)),
                        json.dumps(item.get("evidence", []), ensure_ascii=False),
                        item.get("support_strategy", ""),
                        item.get("source_session_id", ""),
                        item.get("created_at") or item["updated_at"],
                        item["updated_at"],
                    ),
                )
                counts["state_profiles"] += 1
        return counts

    def journal_analytics(self) -> dict[str, Any]:
        journals = self.list_journals(limit=10000)
        points = []
        daily: dict[str, dict[str, Any]] = {}
        weekly: dict[str, dict[str, Any]] = {}

        for journal in reversed(journals):
            created = parse_iso_datetime(journal["created_at"])
            date_key = created.date().isoformat()
            year, week, _ = created.isocalendar()
            week_key = f"{year}-W{week:02d}"
            score = journal.get("mood_score")
            if score is None:
                score = mood_score_for_journal(journal)
            item = {
                "id": journal["id"],
                "session_id": journal["session_id"],
                "date": date_key,
                "week": week_key,
                "created_at": journal["created_at"],
                "score": score,
                "dominant_emotion": journal.get("dominant_emotion") or "未标注",
                "summary": journal["summary"],
                "keywords": journal["keywords"],
                "emotion_curve": journal["emotion_curve"],
                "suggested_next_step": journal["suggested_next_step"],
            }
            points.append(item)

            day = daily.setdefault(
                date_key,
                {"date": date_key, "scores": [], "keywords": {}, "summaries": [], "emotions": {}},
            )
            day["scores"].append(score)
            day["summaries"].append(journal["summary"])
            for keyword in journal["keywords"]:
                day["keywords"][keyword] = day["keywords"].get(keyword, 0) + 1
            emotion = journal.get("dominant_emotion") or "未标注"
            day["emotions"][emotion] = day["emotions"].get(emotion, 0) + 1

            week_row = weekly.setdefault(
                week_key,
                {"week": week_key, "scores": [], "keywords": {}, "summaries": [], "emotions": {}},
            )
            week_row["scores"].append(score)
            week_row["summaries"].append(journal["summary"])
            for keyword in journal["keywords"]:
                week_row["keywords"][keyword] = week_row["keywords"].get(keyword, 0) + 1
            week_row["emotions"][emotion] = week_row["emotions"].get(emotion, 0) + 1

        daily_rows = []
        for day in daily.values():
            avg = sum(day["scores"]) / len(day["scores"])
            keywords = sorted(day["keywords"].items(), key=lambda item: item[1], reverse=True)
            emotions = sorted(day["emotions"].items(), key=lambda item: item[1], reverse=True)
            daily_rows.append(
                {
                    "date": day["date"],
                    "score": round(avg, 2),
                    "count": len(day["scores"]),
                    "keywords": [keyword for keyword, _ in keywords[:5]],
                    "dominant_emotion": emotions[0][0] if emotions else "未标注",
                    "summary": day["summaries"][-1],
                }
            )

        weekly_rows = []
        for week in weekly.values():
            avg = sum(week["scores"]) / len(week["scores"])
            keywords = sorted(week["keywords"].items(), key=lambda item: item[1], reverse=True)
            emotions = sorted(week["emotions"].items(), key=lambda item: item[1], reverse=True)
            summaries = week["summaries"][-3:]
            weekly_rows.append(
                {
                    "week": week["week"],
                    "score": round(avg, 2),
                    "count": len(week["scores"]),
                    "keywords": [keyword for keyword, _ in keywords[:8]],
                    "dominant_emotion": emotions[0][0] if emotions else "未标注",
                    "summary": " / ".join(summaries),
                }
            )

        return {
            "points": points,
            "daily": sorted(daily_rows, key=lambda item: item["date"]),
            "weekly": sorted(weekly_rows, key=lambda item: item["week"], reverse=True),
        }

    def add_mental_status_record(
        self,
        record: dict[str, Any],
        *,
        user_id: str = "default",
    ) -> str:
        record_id = str(uuid.uuid4())
        now = utc_now()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO mental_status_records (
                    id, user_id, record_date, record_time, source_type, source_id,
                    mood, mood_intensity, emotions, energy_level, sleep_quality,
                    social_drive, focus_level, triggers, coping, notes,
                    created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(user_id, record_date, record_time) DO UPDATE SET
                    source_type = excluded.source_type,
                    source_id = excluded.source_id,
                    mood = excluded.mood,
                    mood_intensity = excluded.mood_intensity,
                    emotions = excluded.emotions,
                    energy_level = excluded.energy_level,
                    sleep_quality = excluded.sleep_quality,
                    social_drive = excluded.social_drive,
                    focus_level = excluded.focus_level,
                    triggers = excluded.triggers,
                    coping = excluded.coping,
                    notes = excluded.notes,
                    updated_at = excluded.updated_at
                """,
                (
                    record_id,
                    user_id,
                    record.get("record_date", now[:10]),
                    record.get("record_time"),
                    record.get("source_type", "manual"),
                    record.get("source_id", ""),
                    record.get("mood", ""),
                    record.get("mood_intensity"),
                    json.dumps(record.get("emotions", {}), ensure_ascii=False),
                    record.get("energy_level"),
                    record.get("sleep_quality"),
                    record.get("social_drive"),
                    record.get("focus_level"),
                    record.get("triggers", ""),
                    record.get("coping", ""),
                    record.get("notes", ""),
                    now,
                    now,
                ),
            )
        return record_id

    def list_mental_status_records(
        self,
        *,
        user_id: str = "default",
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT
                    id, user_id, record_date, record_time, source_type, source_id,
                    mood, mood_intensity, emotions, energy_level, sleep_quality,
                    social_drive, focus_level, triggers, coping, notes,
                    created_at, updated_at
                FROM mental_status_records
                WHERE user_id = ?
                ORDER BY record_date DESC, record_time DESC
                LIMIT ?
                """,
                (user_id, limit),
            )
            records = [row_to_dict(row) for row in cursor.fetchall()]
        for record in records:
            try:
                record["emotions"] = json.loads(record["emotions"])
            except (TypeError, json.JSONDecodeError):
                record["emotions"] = {}
        return records

    def mental_status_analytics(
        self,
        *,
        user_id: str = "default",
        days: int = 30,
    ) -> dict[str, Any]:
        records = self.list_mental_status_records(user_id=user_id, limit=10000)
        from datetime import datetime, timedelta, timezone
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).date().isoformat()
        recent = [r for r in records if r["record_date"] >= cutoff]
        if not recent:
            return {"records": [], "trend": [], "mood_distribution": {}, "avg_intensity": None}
        mood_counts: dict[str, int] = {}
        intensity_sum = 0
        intensity_count = 0
        for r in recent:
            mood = r.get("mood") or "未标注"
            mood_counts[mood] = mood_counts.get(mood, 0) + 1
            if r.get("mood_intensity") is not None:
                intensity_sum += r["mood_intensity"]
                intensity_count += 1
        by_date: dict[str, list[dict[str, Any]]] = {}
        for r in recent:
            by_date.setdefault(r["record_date"], []).append(r)
        trend = []
        for date in sorted(by_date):
            day_records = by_date[date]
            avg_intensity = None
            intensities = [r["mood_intensity"] for r in day_records if r.get("mood_intensity") is not None]
            if intensities:
                avg_intensity = round(sum(intensities) / len(intensities), 1)
            trend.append({
                "date": date,
                "count": len(day_records),
                "avg_intensity": avg_intensity,
                "mood": day_records[0].get("mood", "未标注"),
            })
        return {
            "records": recent[:days],
            "trend": trend,
            "mood_distribution": mood_counts,
            "avg_intensity": round(intensity_sum / intensity_count, 1) if intensity_count else None,
        }
