import json
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return dict(row)


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
                """
            )

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
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO messages (id, session_id, role, content, model, metadata, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    session_id,
                    role,
                    content,
                    model,
                    json.dumps(metadata or {}, ensure_ascii=False),
                    utc_now(),
                ),
            )

    def get_session_messages(self, session_id: str) -> list[sqlite3.Row]:
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT role, content, model, created_at
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
                SELECT category, content, evidence, confidence, importance, updated_at
                FROM memories
                ORDER BY importance DESC, updated_at DESC
                LIMIT ?
                """,
                (limit,),
            )
            return list(cursor.fetchall())

    def add_memories(self, session_id: str, memories: list[dict[str, Any]]) -> None:
        with self.connect() as conn:
            for memory in memories[:3]:
                now = utc_now()
                conn.execute(
                    """
                    INSERT INTO memories (
                        id, user_id, category, content, evidence, confidence, importance,
                        source_session_id, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        str(uuid.uuid4()),
                        "default",
                        memory["category"],
                        memory["content"],
                        memory["evidence"],
                        float(memory.get("confidence", 0.5)),
                        int(memory.get("importance", 3)),
                        session_id,
                        now,
                        now,
                    ),
                )

    def add_journal(self, session_id: str, journal: dict[str, Any]) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO journals (
                    id, session_id, summary, emotion_curve, keywords,
                    insights, suggested_next_step, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    session_id,
                    journal.get("summary", ""),
                    json.dumps(journal.get("emotion_curve", []), ensure_ascii=False),
                    json.dumps(journal.get("keywords", []), ensure_ascii=False),
                    json.dumps(journal.get("insights", []), ensure_ascii=False),
                    journal.get("suggested_next_step", ""),
                    utc_now(),
                ),
            )

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
                    SELECT id, session_id, role, content, model, created_at
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
                    SELECT id, session_id, role, content, model, created_at
                    FROM messages
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
            return [row_to_dict(row) for row in cursor.fetchall()]

    def list_memories(self, limit: int = 200) -> list[dict[str, Any]]:
        with self.connect() as conn:
            cursor = conn.execute(
                """
                SELECT
                    id, user_id, category, content, evidence, confidence,
                    importance, source_session_id, created_at, updated_at
                FROM memories
                ORDER BY importance DESC, updated_at DESC
                LIMIT ?
                """,
                (limit,),
            )
            return [row_to_dict(row) for row in cursor.fetchall()]

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
                        insights, suggested_next_step, created_at
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
                        insights, suggested_next_step, created_at
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
