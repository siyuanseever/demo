"""
Prompt 追踪器

拦截并记录每次 LLM 调用的完整信息，包括 prompt 内容、拼接逻辑、响应、耗时等。
支持内存存储和 JSON 持久化。
"""

import json
import time
import uuid
import threading
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Any

from app.llm.base import LLMClient, LLMResponse, Message


@dataclass
class PromptCallRecord:
    """单次 Prompt 调用记录"""
    call_id: str
    timestamp: float
    call_type: str          # 调用类型标识，如 "home_hint", "route_plan", "reply"
    session_id: str | None
    model: str
    messages: list[dict]    # 完整的 messages 列表（即 prompt）
    full_prompt_text: str   # 拼接后的完整 prompt 文本
    temperature: float
    max_tokens: int
    response_format: dict | None
    response_content: str
    response_model: str
    response_time_sec: float
    prompt_tokens_est: int  # 估算的 prompt token 数
    response_tokens_est: int  # 估算的 response token 数
    metadata: dict = field(default_factory=dict)


class PromptTracker:
    """Prompt 调用追踪器（单例）"""

    _instance = None
    _lock = threading.Lock()
    _records: list[PromptCallRecord]
    _enabled: bool
    _storage_dir: Path

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._records = []
                    cls._instance._lock = threading.Lock()
                    cls._instance._enabled = True
                    cls._instance._storage_dir = Path("data/prompt_logs")
                    cls._instance._storage_dir.mkdir(parents=True, exist_ok=True)
        return cls._instance

    def set_enabled(self, enabled: bool) -> None:
        self._enabled = enabled

    def is_enabled(self) -> bool:
        return self._enabled

    def record(
        self,
        call_type: str,
        session_id: str | None,
        model: str,
        messages: list[Message],
        temperature: float,
        max_tokens: int,
        response_format: dict | None,
        response: LLMResponse,
        response_time_sec: float,
        metadata: dict | None = None,
    ) -> PromptCallRecord | None:
        if not self._enabled:
            return None

        # 估算 token 数（粗略: 1 token ≈ 1.5 中文字符 或 4 英文字符）
        full_text = "\n\n".join(
            f"[{m.get('role', 'unknown')}] {m.get('content', '')}"
            for m in messages
        )
        prompt_tokens_est = self._estimate_tokens(full_text)
        response_tokens_est = self._estimate_tokens(response.content)

        record = PromptCallRecord(
            call_id=str(uuid.uuid4())[:8],
            timestamp=time.time(),
            call_type=call_type,
            session_id=session_id,
            model=model,
            messages=[dict(m) for m in messages],
            full_prompt_text=full_text,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format=response_format,
            response_content=response.content,
            response_model=response.model,
            response_time_sec=response_time_sec,
            prompt_tokens_est=prompt_tokens_est,
            response_tokens_est=response_tokens_est,
            metadata=metadata or {},
        )

        with self._lock:
            self._records.append(record)
            # 自动持久化到文件
            self._persist(record)

        return record

    def _estimate_tokens(self, text: str) -> int:
        """粗略估算 token 数"""
        if not text:
            return 0
        # 简单估算：中文字符按 1.5 chars/token，英文按 4 chars/token
        cn_chars = sum(1 for c in text if '\u4e00' <= c <= '\u9fff')
        other_chars = len(text) - cn_chars
        return int(cn_chars / 1.5 + other_chars / 4)

    def _persist(self, record: PromptCallRecord) -> None:
        """持久化单条记录到 JSONL"""
        date_str = datetime.now().strftime("%Y%m%d")
        path = self._storage_dir / f"prompt_calls_{date_str}.jsonl"
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(asdict(record), ensure_ascii=False) + "\n")

    def get_records(
        self,
        call_type: str | None = None,
        session_id: str | None = None,
        limit: int = 100,
    ) -> list[PromptCallRecord]:
        with self._lock:
            records = list(self._records)
        if call_type:
            records = [r for r in records if r.call_type == call_type]
        if session_id:
            records = [r for r in records if r.session_id == session_id]
        return records[-limit:]

    def get_record(self, call_id: str) -> PromptCallRecord | None:
        with self._lock:
            for r in reversed(self._records):
                if r.call_id == call_id:
                    return r
        return None

    def get_stats(self) -> dict[str, Any]:
        with self._lock:
            records = list(self._records)
        if not records:
            return {"total_calls": 0}

        total_prompt_tokens = sum(r.prompt_tokens_est for r in records)
        total_response_tokens = sum(r.response_tokens_est for r in records)
        total_time = sum(r.response_time_sec for r in records)

        by_type: dict[str, list[PromptCallRecord]] = {}
        for r in records:
            by_type.setdefault(r.call_type, []).append(r)

        return {
            "total_calls": len(records),
            "total_prompt_tokens_est": total_prompt_tokens,
            "total_response_tokens_est": total_response_tokens,
            "avg_response_time_sec": round(total_time / len(records), 3) if records else 0,
            "by_type": {
                t: {
                    "count": len(rs),
                    "avg_time_sec": round(sum(r.response_time_sec for r in rs) / len(rs), 3),
                    "avg_prompt_tokens": round(sum(r.prompt_tokens_est for r in rs) / len(rs), 1),
                    "avg_response_tokens": round(sum(r.response_tokens_est for r in rs) / len(rs), 1),
                }
                for t, rs in by_type.items()
            },
        }

    def clear(self) -> None:
        with self._lock:
            self._records.clear()

    def to_dict_list(self, limit: int = 100) -> list[dict]:
        with self._lock:
            records = list(self._records)
        return [asdict(r) for r in records[-limit:]]


class TrackedLLMClient:
    """LLMClient 包装器，自动追踪每次调用"""

    def __init__(self, client: LLMClient, tracker: PromptTracker | None = None):
        self._client = client
        self._tracker = tracker or PromptTracker()
        self._call_context: dict = {}

    def set_context(self, call_type: str = "", session_id: str | None = None, metadata: dict | None = None):
        """设置下一次调用的上下文信息"""
        self._call_context = {
            "call_type": call_type,
            "session_id": session_id,
            "metadata": metadata or {},
        }

    def chat(
        self,
        messages: list[Message],
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
        thinking: str | None = None,
        reasoning_effort: str | None = None,
    ) -> LLMResponse:
        started_at = time.monotonic()
        response = self._client.chat(
            messages,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format=response_format,
            thinking=thinking,
            reasoning_effort=reasoning_effort,
        )
        elapsed = time.monotonic() - started_at

        ctx = self._call_context
        self._tracker.record(
            call_type=ctx.get("call_type", "unknown"),
            session_id=ctx.get("session_id"),
            model=getattr(self._client, "model", "unknown"),
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format=response_format,
            response=response,
            response_time_sec=elapsed,
            metadata=ctx.get("metadata", {}),
        )
        # 清空上下文，避免污染下一次调用
        self._call_context = {}
        return response


def wrap_llm_client(client: LLMClient) -> TrackedLLMClient:
    """包装 LLMClient，启用 Prompt 追踪"""
    return TrackedLLMClient(client)
