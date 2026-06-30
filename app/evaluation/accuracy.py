"""
准确率评估模块

定义测试用例并对比预期输出与实际输出，支持精确匹配、包含匹配、自定义验证器。
"""

import time
import traceback
from dataclasses import dataclass, field
from typing import Any, Callable
from app.evaluation.timer import timed


@dataclass
class AccuracyResult:
    """单次准确率测试结果"""
    test_name: str
    passed: bool
    expected: Any = None
    actual: Any = None
    message: str = ""
    elapsed_sec: float = 0.0
    module: str = ""


class AccuracyTest:
    """准确率测试基类"""

    def __init__(self, name: str, module: str = ""):
        self.name = name
        self.module = module
        self.results: list[AccuracyResult] = []

    def assert_equal(self, test_name: str, expected: Any, actual: Any) -> bool:
        passed = expected == actual
        result = AccuracyResult(
            test_name=test_name,
            passed=passed,
            expected=expected,
            actual=actual,
            message="值匹配" if passed else f"期望 {expected!r}, 实际 {actual!r}",
            module=self.module,
        )
        self.results.append(result)
        return passed

    def assert_contains(self, test_name: str, container: Any, item: Any) -> bool:
        passed = item in container
        result = AccuracyResult(
            test_name=test_name,
            passed=passed,
            expected=f"包含 {item!r}",
            actual=container,
            message="包含检查通过" if passed else f"{container!r} 不包含 {item!r}",
            module=self.module,
        )
        self.results.append(result)
        return passed

    def assert_true(self, test_name: str, condition: bool, message: str = "") -> bool:
        result = AccuracyResult(
            test_name=test_name,
            passed=bool(condition),
            expected=True,
            actual=condition,
            message=message or ("条件为真" if condition else "条件为假"),
            module=self.module,
        )
        self.results.append(result)
        return bool(condition)

    def assert_custom(
        self,
        test_name: str,
        validator: Callable[[], bool],
        expected_desc: str = "自定义验证",
        actual_desc: str = "",
    ) -> bool:
        try:
            passed = validator()
        except Exception as e:
            passed = False
            actual_desc = f"异常: {e}"
        result = AccuracyResult(
            test_name=test_name,
            passed=passed,
            expected=expected_desc,
            actual=actual_desc,
            message="验证通过" if passed else (actual_desc or "自定义验证失败"),
            module=self.module,
        )
        self.results.append(result)
        return passed

    def run(self) -> list[AccuracyResult]:
        """子类重写此方法，返回测试结果列表"""
        return self.results

    def summary(self) -> dict[str, Any]:
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        return {
            "module": self.module,
            "test_name": self.name,
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate": round(passed / total, 4) if total else 0,
            "details": [
                {
                    "test_name": r.test_name,
                    "passed": r.passed,
                    "message": r.message,
                    "elapsed_sec": r.elapsed_sec,
                }
                for r in self.results
            ],
        }


def accuracy_suite(tests: list[AccuracyTest]) -> dict[str, Any]:
    """运行一组准确率测试并返回汇总结果"""
    all_results = []
    for test in tests:
        try:
            with timed(f"accuracy.{test.name}") as t:
                test.run()
            for r in test.results:
                r.elapsed_sec = t.elapsed
        except Exception as e:
            test.results.append(AccuracyResult(
                test_name=f"{test.name}.setup",
                passed=False,
                message=f"测试运行异常: {e}\n{traceback.format_exc()}",
                module=test.module,
            ))
        all_results.extend(test.results)

    total = len(all_results)
    passed = sum(1 for r in all_results if r.passed)
    by_module: dict[str, list[AccuracyResult]] = {}
    for r in all_results:
        by_module.setdefault(r.module or "unknown", []).append(r)

    return {
        "total": total,
        "passed": passed,
        "failed": total - passed,
        "pass_rate": round(passed / total, 4) if total else 0,
        "by_module": {
            mod: {
                "total": len(rs),
                "passed": sum(1 for r in rs if r.passed),
                "pass_rate": round(sum(1 for r in rs if r.passed) / len(rs), 4) if rs else 0,
            }
            for mod, rs in by_module.items()
        },
        "details": all_results,
    }
