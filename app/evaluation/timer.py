"""
耗时追踪模块

提供装饰器和上下文管理器两种模式，用于精确统计函数调用耗时。
支持多次调用的百分位数统计(min, max, avg, p50, p95, p99)。
"""

import time
import functools
import threading
from collections import defaultdict
from typing import Callable, Any


class TimerStats:
    """单个函数的耗时统计"""

    def __init__(self, name: str):
        self.name = name
        self.records: list[float] = []
        self._lock = threading.Lock()

    def add(self, elapsed_sec: float) -> None:
        with self._lock:
            self.records.append(elapsed_sec)

    @property
    def count(self) -> int:
        return len(self.records)

    @property
    def total(self) -> float:
        return sum(self.records)

    @property
    def min(self) -> float:
        return min(self.records) if self.records else 0.0

    @property
    def max(self) -> float:
        return max(self.records) if self.records else 0.0

    @property
    def avg(self) -> float:
        return self.total / self.count if self.count else 0.0

    @property
    def p50(self) -> float:
        return self._percentile(0.5)

    @property
    def p95(self) -> float:
        return self._percentile(0.95)

    @property
    def p99(self) -> float:
        return self._percentile(0.99)

    def _percentile(self, p: float) -> float:
        if not self.records:
            return 0.0
        sorted_records = sorted(self.records)
        k = (len(sorted_records) - 1) * p
        f = int(k)
        c = f + 1 if f + 1 < len(sorted_records) else f
        if f == c:
            return sorted_records[f]
        return sorted_records[f] * (c - k) + sorted_records[c] * (k - f)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "count": self.count,
            "total_sec": round(self.total, 4),
            "min_sec": round(self.min, 4),
            "max_sec": round(self.max, 4),
            "avg_sec": round(self.avg, 4),
            "p50_sec": round(self.p50, 4),
            "p95_sec": round(self.p95, 4),
            "p99_sec": round(self.p99, 4),
        }


class Timer:
    """全局耗时追踪器"""

    _instance = None
    _lock = threading.Lock()
    _stats: dict[str, TimerStats]

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._stats = {}
                    cls._instance._lock = threading.Lock()
        return cls._instance

    def record(self, name: str, elapsed_sec: float) -> None:
        with self._lock:
            if name not in self._stats:
                self._stats[name] = TimerStats(name)
            self._stats[name].add(elapsed_sec)

    def get_stats(self, name: str | None = None) -> dict:
        with self._lock:
            if name:
                stat = self._stats.get(name)
                return stat.to_dict() if stat else {}
            return {k: v.to_dict() for k, v in self._stats.items()}

    def reset(self) -> None:
        with self._lock:
            self._stats.clear()

    def summary(self) -> list[dict]:
        with self._lock:
            return [s.to_dict() for s in sorted(self._stats.values(), key=lambda x: x.name)]


class timed:
    """上下文管理器: with timed('label') as t: ..."""

    def __init__(self, name: str, timer: Timer | None = None):
        self.name = name
        self.timer = timer or Timer()
        self.started_at: float = 0.0
        self.elapsed: float = 0.0

    def __enter__(self):
        self.started_at = time.monotonic()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.elapsed = time.monotonic() - self.started_at
        self.timer.record(self.name, self.elapsed)
        return False


def timed_decorator(name: str | None = None, timer: Timer | None = None):
    """装饰器: @timed_decorator() def func(): ..."""

    def decorator(func: Callable) -> Callable:
        label = name or f"{func.__module__}.{func.__qualname__}"
        t = timer or Timer()

        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            started = time.monotonic()
            try:
                return func(*args, **kwargs)
            finally:
                t.record(label, time.monotonic() - started)

        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs):
            started = time.monotonic()
            try:
                return await func(*args, **kwargs)
            finally:
                t.record(label, time.monotonic() - started)

        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        return wrapper

    return decorator


import asyncio
