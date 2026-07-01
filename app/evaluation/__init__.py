"""
评估框架 (Evaluation Framework)

为 Codex 参与维护的项目提供多维度评估能力：
- 耗时评估: 统计各模块调用耗时
- 性能评估: 内存、CPU、吞吐量
- 准确率评估: 功能正确性验证
- 完整性评估: 模块接口与依赖完整性
- 鲁棒性评估: 边界条件、异常处理、并发安全

一键运行: python3 -m app.evaluation.runner
"""

from app.evaluation.timer import Timer, timed
from app.evaluation.metrics import MetricsCollector, MetricSnapshot
from app.evaluation.accuracy import AccuracyTest, accuracy_suite
from app.evaluation.robustness import RobustnessTest, robustness_suite
from app.evaluation.completeness import CompletenessChecker
from app.evaluation.reporter import ReportGenerator

__all__ = [
    "Timer",
    "timed",
    "MetricsCollector",
    "MetricSnapshot",
    "AccuracyTest",
    "accuracy_suite",
    "RobustnessTest",
    "robustness_suite",
    "CompletenessChecker",
    "ReportGenerator",
]
