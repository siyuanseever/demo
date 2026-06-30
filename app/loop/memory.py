"""
Loop 跨迭代记忆

持久化存储在 data/loop_memory.jsonl，支持按类型和标签检索。
默认只加载最近 50 条，旧记录自动归档。
"""

import json
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any


_MEMORY_PATH = Path("data/loop_memory.jsonl")
_ARCHIVE_PATH = Path("data/loop_memory_archive.jsonl")
_MAX_ACTIVE = 50


@dataclass
class LoopMemoryEntry:
    """单条记忆"""

    timestamp: float
    iteration: int
    type: str          # decision | observation | error | pattern
    content: str
    tags: list[str] = field(default_factory=list)


class LoopMemory:
    """跨迭代记忆管理器"""

    def __init__(self):
        _MEMORY_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._entries: list[LoopMemoryEntry] = []

    def add_memory(
        self,
        type: str,
        content: str,
        iteration: int = 0,
        tags: list[str] | None = None,
    ) -> None:
        """添加一条记忆"""
        entry = LoopMemoryEntry(
            timestamp=time.time(),
            iteration=iteration,
            type=type,
            content=content,
            tags=tags or [],
        )
        self._entries.append(entry)
        self._persist(entry)
        self._maybe_archive()

    def query_memories(
        self,
        query: str = "",
        type_filter: str | None = None,
        tag_filter: str | None = None,
        limit: int = 20,
    ) -> list[LoopMemoryEntry]:
        """查询记忆，支持关键词、类型、标签过滤"""
        # 加载最近条目
        self._load_recent()

        results = self._entries[:]

        if type_filter:
            results = [e for e in results if e.type == type_filter]

        if tag_filter:
            results = [e for e in results if tag_filter in e.tags]

        if query:
            q = query.lower()
            results = [e for e in results if q in e.content.lower() or any(q in t.lower() for t in e.tags)]

        # 按时间倒序，取最近 limit 条
        results = sorted(results, key=lambda e: e.timestamp, reverse=True)
        return results[:limit]

    def list_all(self, limit: int = 50) -> list[LoopMemoryEntry]:
        """列出所有记忆"""
        self._load_recent()
        return sorted(self._entries, key=lambda e: e.timestamp, reverse=True)[:limit]

    def clear(self) -> None:
        """清空所有记忆"""
        if _MEMORY_PATH.exists():
            _MEMORY_PATH.unlink()
        if _ARCHIVE_PATH.exists():
            _ARCHIVE_PATH.unlink()
        self._entries = []
        print("✅ Loop 记忆已清空")

    def _persist(self, entry: LoopMemoryEntry) -> None:
        """持久化单条记忆"""
        with open(_MEMORY_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(asdict(entry), ensure_ascii=False) + "\n")

    def _load_recent(self) -> None:
        """从磁盘加载最近记忆"""
        if not _MEMORY_PATH.exists():
            return

        self._entries = []
        try:
            with open(_MEMORY_PATH, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    data = json.loads(line)
                    self._entries.append(LoopMemoryEntry(
                        timestamp=data.get("timestamp", 0),
                        iteration=data.get("iteration", 0),
                        type=data.get("type", "observation"),
                        content=data.get("content", ""),
                        tags=data.get("tags", []),
                    ))
        except (json.JSONDecodeError, OSError):
            pass

    def _maybe_archive(self) -> None:
        """若活跃记忆超过上限，归档旧记录"""
        if len(self._entries) <= _MAX_ACTIVE:
            return

        to_archive = self._entries[:-(_MAX_ACTIVE)]
        self._entries = self._entries[-(_MAX_ACTIVE):]

        with open(_ARCHIVE_PATH, "a", encoding="utf-8") as f:
            for entry in to_archive:
                f.write(json.dumps(asdict(entry), ensure_ascii=False) + "\n")

        # 重写活跃记忆文件
        with open(_MEMORY_PATH, "w", encoding="utf-8") as f:
            for entry in self._entries:
                f.write(json.dumps(asdict(entry), ensure_ascii=False) + "\n")
