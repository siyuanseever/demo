import json
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any

from app.memory.schema import MEMORY_SUBCATEGORIES


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
    item["knowledge_card_ids"] = metadata.get("knowledge_card_ids", [])
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
                """
            )
            self._ensure_column(conn, "memories", "subcategory", "TEXT NOT NULL DEFAULT 'general'")
            self._ensure_column(conn, "memories", "keywords", "TEXT NOT NULL DEFAULT '[]'")
            self._ensure_column(conn, "memories", "status", "TEXT NOT NULL DEFAULT 'active'")
            self._ensure_column(conn, "memories", "merged_into_id", "TEXT")
            self._ensure_column(conn, "memories", "merge_note", "TEXT NOT NULL DEFAULT ''")
            self._ensure_column(conn, "journals", "mood_score", "INTEGER")
            self._ensure_column(conn, "journals", "dominant_emotion", "TEXT NOT NULL DEFAULT ''")

    def _ensure_column(
        self,
        conn: sqlite3.Connection,
        table: str,
        column: str,
        definition: str,
    ) -> None:
        existing = {
            row["name"]
            for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
        }
        if column not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")

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

    def recent_memories(self, limit: int = 12) -> list[sqlite3.Row]:
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
            return list(cursor.fetchall())

    def add_memory(self, session_id: str, memory: dict[str, Any]) -> str:
        memory_id = str(uuid.uuid4())
        now = utc_now()
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
                    memory.get("subcategory", "general"),
                    json.dumps(memory.get("keywords", []), ensure_ascii=False),
                    memory["content"],
                    memory["evidence"],
                    float(memory.get("confidence", 0.5)),
                    int(memory.get("importance", 3)),
                    memory.get("status", "active"),
                    session_id,
                    now,
                    now,
                ),
            )
        return memory_id

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
            if key in updates:
                fields.append(f"{key} = ?")
                values.append(updates[key])
        if "keywords" in updates:
            fields.append("keywords = ?")
            values.append(json.dumps(updates["keywords"], ensure_ascii=False))
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
            "evidence": json.dumps(evidence[:5], ensure_ascii=False),
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
            "evidence": evidence[:5],
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

    def list_memories(self, limit: int = 200) -> list[dict[str, Any]]:
        with self.connect() as conn:
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
            try:
                memory["keywords"] = json.loads(memory["keywords"])
            except (TypeError, json.JSONDecodeError):
                memory["keywords"] = []
        return memories

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
                LIMIT 30
                """,
                (memory["category"],),
            )
            candidates = [row_to_dict(row) for row in cursor.fetchall()]
        for candidate in candidates:
            try:
                candidate["keywords"] = json.loads(candidate["keywords"])
            except (TypeError, json.JSONDecodeError):
                candidate["keywords"] = []
            overlap = keywords.intersection(candidate["keywords"])
            candidate["_score"] = (
                2 * int(candidate["subcategory"] == memory.get("subcategory"))
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
