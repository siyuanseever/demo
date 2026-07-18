"""Conservative, auditable nightly reflection for long-term memories.

The first policy is deliberately deterministic.  More capable policies (for
example an LLM or learned ADD/UPDATE/DELETE/SUMMARIZE/NOOP policy) can produce
the same ``ReflectionAction`` objects without changing scheduling or storage.
"""

from __future__ import annotations

import logging
import re
import threading
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import StrEnum
from typing import Callable, Protocol

from app.memory.store import Store, parse_iso_datetime


LOGGER = logging.getLogger(__name__)
REFLECTION_SESSION_PREFIX = "reflection:"


class ReflectionOperation(StrEnum):
    ADD = "add"
    UPDATE = "update"
    DELETE = "delete"
    SUMMARIZE = "summarize"
    NOOP = "noop"


@dataclass(frozen=True)
class ReflectionAction:
    operation: ReflectionOperation
    memory_id: str
    target_memory_id: str | None = None
    reason: str = ""
    memory: dict | None = None


class ReflectionPolicy(Protocol):
    def plan(self, memories: list[dict], *, now: datetime) -> list[ReflectionAction]: ...


def _normalized_content(value: str) -> str:
    text = unicodedata.normalize("NFKC", str(value or "")).strip().lower()
    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"[，。！？；：、,.!?;:]+", "", text)
    return text


class ConservativeReflectionPolicy:
    """Merge exact duplicates and archive only clearly disposable memories."""

    def __init__(self, *, stale_days: int = 180) -> None:
        self.stale_days = max(30, stale_days)

    def plan(self, memories: list[dict], *, now: datetime) -> list[ReflectionAction]:
        active = [item for item in memories if item.get("status") == "active"]
        actions: list[ReflectionAction] = []
        groups: dict[tuple[str, str, str], list[dict]] = {}

        for memory in active:
            normalized = _normalized_content(memory.get("content", ""))
            if not normalized:
                actions.append(ReflectionAction(
                    ReflectionOperation.DELETE,
                    memory["id"],
                    reason="夜间反思：空内容记忆已软删除。",
                ))
                continue
            key = (memory.get("category", ""), memory.get("subcategory", ""), normalized)
            groups.setdefault(key, []).append(memory)

        handled: set[str] = {action.memory_id for action in actions}
        for group in groups.values():
            if len(group) < 2:
                continue
            ranked = sorted(
                group,
                key=lambda item: (
                    int(item.get("importance", 0)),
                    float(item.get("confidence", 0)),
                    item.get("updated_at", ""),
                ),
                reverse=True,
            )
            target = ranked[0]
            for duplicate in ranked[1:]:
                handled.add(duplicate["id"])
                actions.append(ReflectionAction(
                    ReflectionOperation.UPDATE,
                    duplicate["id"],
                    target_memory_id=target["id"],
                    reason=f"夜间反思：与记忆 {target['id']} 内容重复，已合并。",
                ))

        cutoff = now - timedelta(days=self.stale_days)
        for memory in active:
            if memory["id"] in handled:
                continue
            updated_at = parse_iso_datetime(memory["updated_at"])
            if updated_at.tzinfo is None:
                updated_at = updated_at.replace(tzinfo=now.tzinfo)
            if (
                int(memory.get("importance", 0)) <= 1
                and float(memory.get("confidence", 0)) <= 0.2
                and updated_at <= cutoff
            ):
                actions.append(ReflectionAction(
                    ReflectionOperation.DELETE,
                    memory["id"],
                    reason=(
                        f"夜间反思：重要度和置信度均很低，且超过 {self.stale_days} 天未更新；"
                        "已软删除，可从审计记录恢复。"
                    ),
                ))

        if not actions:
            actions.append(ReflectionAction(
                ReflectionOperation.NOOP,
                "",
                reason="夜间反思：没有发现需要安全整理的记忆。",
            ))
        return actions


class MemoryReflector:
    def __init__(self, store: Store, policy: ReflectionPolicy) -> None:
        self.store = store
        self.policy = policy

    def reflect(self, *, now: datetime | None = None) -> dict:
        current = now or datetime.now().astimezone()
        reflection_date = current.date().isoformat()
        run_id = self.store.start_memory_reflection(reflection_date)
        if run_id is None:
            return {"status": "skipped", "reflection_date": reflection_date}

        counts = {"merged": 0, "archived": 0, "noop": 0}
        session_id = f"{REFLECTION_SESSION_PREFIX}{run_id}"
        try:
            memories = self.store.list_memories(limit=10000)
            by_id = {item["id"]: item for item in memories}
            actions = self.policy.plan(memories, now=current)
            for action in actions:
                if action.operation == ReflectionOperation.ADD and action.memory:
                    memory_id = self.store.add_memory(session_id, action.memory)
                    self.store.add_memory_event(
                        session_id,
                        action="reflect_add",
                        memory=action.memory,
                        memory_id=memory_id,
                        reason=action.reason,
                    )
                elif action.operation == ReflectionOperation.UPDATE and action.target_memory_id:
                    memory = by_id[action.memory_id]
                    self.store.mark_memory(
                        action.memory_id,
                        status="merged",
                        merge_note=action.reason,
                        merged_into_id=action.target_memory_id,
                    )
                    self.store.add_memory_event(
                        session_id,
                        action="reflect_merge",
                        memory=memory,
                        memory_id=action.memory_id,
                        reason=action.reason,
                    )
                    counts["merged"] += 1
                elif action.operation == ReflectionOperation.UPDATE and action.memory:
                    self.store.update_memory(action.memory_id, action.memory, merge_note=action.reason)
                    self.store.add_memory_event(
                        session_id,
                        action="reflect_update",
                        memory=action.memory,
                        memory_id=action.memory_id,
                        reason=action.reason,
                    )
                elif action.operation == ReflectionOperation.DELETE:
                    memory = by_id[action.memory_id]
                    self.store.mark_memory(
                        action.memory_id,
                        status="archived",
                        merge_note=action.reason,
                    )
                    self.store.add_memory_event(
                        session_id,
                        action="reflect_archive",
                        memory=memory,
                        memory_id=action.memory_id,
                        reason=action.reason,
                    )
                    counts["archived"] += 1
                elif action.operation == ReflectionOperation.SUMMARIZE and action.memory:
                    self.store.update_memory(action.memory_id, action.memory, merge_note=action.reason)
                    self.store.add_memory_event(
                        session_id,
                        action="reflect_summarize",
                        memory=action.memory,
                        memory_id=action.memory_id,
                        reason=action.reason,
                    )
                elif action.operation == ReflectionOperation.NOOP:
                    counts["noop"] += 1
                else:
                    LOGGER.warning("reflection action missing required payload: %s", action.operation)
            self.store.finish_memory_reflection(
                run_id,
                status="completed",
                merged_count=counts["merged"],
                archived_count=counts["archived"],
                noop_count=counts["noop"],
            )
            return {
                "status": "completed",
                "reflection_date": reflection_date,
                **counts,
            }
        except Exception as error:
            self.store.finish_memory_reflection(run_id, status="failed", error=str(error))
            raise


class NightlyReflectionScheduler:
    """Small in-process scheduler that runs only during the configured hour."""

    def __init__(
        self,
        reflector: MemoryReflector,
        *,
        hour: int = 2,
        check_interval_seconds: float = 60,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        if not 0 <= hour <= 23:
            raise ValueError("memory reflection hour must be between 0 and 23")
        self.reflector = reflector
        self.hour = hour
        self.check_interval_seconds = max(1, check_interval_seconds)
        self.clock = clock or (lambda: datetime.now().astimezone())
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def run_if_due(self) -> dict | None:
        now = self.clock()
        if now.hour != self.hour:
            return None
        return self.reflector.reflect(now=now)

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._thread = threading.Thread(
            target=self._run,
            name="memory-reflection",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                self.run_if_due()
            except Exception:
                LOGGER.exception("nightly memory reflection failed")
            self._stop.wait(self.check_interval_seconds)
