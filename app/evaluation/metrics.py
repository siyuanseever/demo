"""
指标收集与聚合模块

支持性能指标(内存、CPU)、业务指标(成功率、吞吐量)的收集与快照。
"""

import time
import os
import threading
from dataclasses import dataclass, field, asdict
from typing import Any
from collections import defaultdict

try:
    import psutil
    _HAS_PSUTIL = True
except ImportError:
    _HAS_PSUTIL = False


@dataclass
class MetricSnapshot:
    """单次指标快照"""
    timestamp: float
    metric_name: str
    value: float
    unit: str = ""
    labels: dict[str, str] = field(default_factory=dict)


class MetricsCollector:
    """指标收集器: 支持计数器、计时器、 gauges"""

    def __init__(self):
        self._counters: dict[str, int] = defaultdict(int)
        self._gauges: dict[str, float] = {}
        self._histograms: dict[str, list[float]] = defaultdict(list)
        self._snapshots: list[MetricSnapshot] = []
        self._lock = threading.Lock()
        self._process = psutil.Process(os.getpid()) if _HAS_PSUTIL else None

    def increment(self, name: str, value: int = 1, labels: dict | None = None) -> None:
        with self._lock:
            key = self._key(name, labels)
            self._counters[key] += value
            self._snapshots.append(MetricSnapshot(
                timestamp=time.time(), metric_name=name, value=float(self._counters[key]),
                unit="count", labels=labels or {}
            ))

    def gauge(self, name: str, value: float, labels: dict | None = None) -> None:
        with self._lock:
            key = self._key(name, labels)
            self._gauges[key] = value
            self._snapshots.append(MetricSnapshot(
                timestamp=time.time(), metric_name=name, value=value,
                unit="gauge", labels=labels or {}
            ))

    def record(self, name: str, value: float, labels: dict | None = None) -> None:
        with self._lock:
            key = self._key(name, labels)
            self._histograms[key].append(value)
            self._snapshots.append(MetricSnapshot(
                timestamp=time.time(), metric_name=name, value=value,
                unit="seconds", labels=labels or {}
            ))

    def record_memory(self) -> dict[str, float]:
        """记录当前进程内存使用"""
        if self._process is None:
            self.gauge("process_memory_rss_mb", 0.0)
            self.gauge("process_memory_vms_mb", 0.0)
            return {"rss_mb": 0.0, "vms_mb": 0.0}
        info = self._process.memory_info()
        rss_mb = info.rss / 1024 / 1024
        vms_mb = info.vms / 1024 / 1024
        self.gauge("process_memory_rss_mb", rss_mb)
        self.gauge("process_memory_vms_mb", vms_mb)
        return {"rss_mb": rss_mb, "vms_mb": vms_mb}

    def record_cpu(self) -> float:
        """记录当前进程CPU使用率"""
        if self._process is None:
            self.gauge("process_cpu_percent", 0.0)
            return 0.0
        cpu_percent = self._process.cpu_percent(interval=0.1)
        self.gauge("process_cpu_percent", cpu_percent)
        return cpu_percent

    def _key(self, name: str, labels: dict | None) -> str:
        if not labels:
            return name
        label_str = ",".join(f"{k}={v}" for k, v in sorted(labels.items()))
        return f"{name}{{{label_str}}}"

    def summary(self) -> dict[str, Any]:
        with self._lock:
            result = {
                "counters": dict(self._counters),
                "gauges": dict(self._gauges),
                "histograms": {},
            }
            for key, values in self._histograms.items():
                if not values:
                    continue
                sorted_vals = sorted(values)
                n = len(sorted_vals)
                result["histograms"][key] = {
                    "count": n,
                    "min": round(sorted_vals[0], 4),
                    "max": round(sorted_vals[-1], 4),
                    "avg": round(sum(sorted_vals) / n, 4),
                    "p50": round(sorted_vals[int(n * 0.5)], 4) if n > 0 else 0,
                    "p95": round(sorted_vals[int(n * 0.95)], 4) if n > 0 else 0,
                    "p99": round(sorted_vals[int(n * 0.99)], 4) if n > 0 else 0,
                }
            return result

    def get_snapshots(self) -> list[dict]:
        with self._lock:
            return [asdict(s) for s in self._snapshots]

    def reset(self) -> None:
        with self._lock:
            self._counters.clear()
            self._gauges.clear()
            self._histograms.clear()
            self._snapshots.clear()
