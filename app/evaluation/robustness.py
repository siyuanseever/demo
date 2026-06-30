"""
鲁棒性评估模块

测试系统在边界条件、异常输入、并发场景下的稳定性。
覆盖: 空输入、超长输入、特殊字符、并发访问、资源耗尽模拟。
"""

import time
import traceback
import threading
import concurrent.futures
from dataclasses import dataclass
from typing import Any, Callable
from app.evaluation.timer import timed


@dataclass
class RobustnessResult:
    test_name: str
    passed: bool
    module: str
    scenario: str
    message: str
    elapsed_sec: float = 0.0
    exception: str = ""


class RobustnessTest:
    """鲁棒性测试基类"""

    def __init__(self, name: str, module: str = ""):
        self.name = name
        self.module = module
        self.results: list[RobustnessResult] = []

    def test_edge_case(
        self,
        test_name: str,
        func: Callable,
        *args,
        should_raise: type[Exception] | None = None,
        **kwargs,
    ) -> bool:
        """测试边界条件: 预期不抛异常(或预期抛指定异常)"""
        scenario = f"edge_case({test_name})"
        start = time.monotonic()
        try:
            result = func(*args, **kwargs)
            elapsed = time.monotonic() - start
            if should_raise:
                self.results.append(RobustnessResult(
                    test_name=test_name, passed=False, module=self.module,
                    scenario=scenario, message=f"期望抛出 {should_raise.__name__}, 但未抛出",
                    elapsed_sec=elapsed,
                ))
                return False
            self.results.append(RobustnessResult(
                test_name=test_name, passed=True, module=self.module,
                scenario=scenario, message=f"正常返回: {type(result).__name__}",
                elapsed_sec=elapsed,
            ))
            return True
        except Exception as e:
            elapsed = time.monotonic() - start
            if should_raise and isinstance(e, should_raise):
                self.results.append(RobustnessResult(
                    test_name=test_name, passed=True, module=self.module,
                    scenario=scenario, message=f"按预期抛出 {type(e).__name__}: {e}",
                    elapsed_sec=elapsed,
                ))
                return True
            self.results.append(RobustnessResult(
                test_name=test_name, passed=False, module=self.module,
                scenario=scenario, message=f"未预期异常: {type(e).__name__}: {e}",
                elapsed_sec=elapsed, exception=traceback.format_exc(),
            ))
            return False

    def test_concurrent(
        self,
        test_name: str,
        func: Callable,
        args_list: list[tuple],
        max_workers: int = 10,
        timeout: float = 30.0,
    ) -> bool:
        """并发测试: 多次调用同一函数"""
        scenario = f"concurrent({len(args_list)}次, {max_workers}线程)"
        start = time.monotonic()
        errors = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [executor.submit(func, *args) for args in args_list]
            for i, future in enumerate(concurrent.futures.as_completed(futures, timeout=timeout)):
                try:
                    future.result(timeout=timeout)
                except Exception as e:
                    errors.append(f"第{i}次: {type(e).__name__}: {e}")
        elapsed = time.monotonic() - start
        passed = len(errors) == 0
        self.results.append(RobustnessResult(
            test_name=test_name, passed=passed, module=self.module,
            scenario=scenario,
            message=f"全部通过" if passed else f"失败 {len(errors)}/{len(args_list)}: {errors[:3]}",
            elapsed_sec=elapsed,
        ))
        return passed

    def test_stress(
        self,
        test_name: str,
        func: Callable,
        iterations: int = 100,
        args: tuple = (),
        kwargs: dict | None = None,
    ) -> bool:
        """压力测试: 连续多次调用"""
        scenario = f"stress({iterations}次连续调用)"
        start = time.monotonic()
        errors = []
        kwargs = kwargs or {}
        for i in range(iterations):
            try:
                func(*args, **kwargs)
            except Exception as e:
                errors.append(f"第{i}次: {type(e).__name__}: {e}")
                if len(errors) >= 5:
                    break
        elapsed = time.monotonic() - start
        passed = len(errors) == 0
        self.results.append(RobustnessResult(
            test_name=test_name, passed=passed, module=self.module,
            scenario=scenario,
            message=f"全部通过, 总耗时 {elapsed:.2f}s" if passed else f"失败 {len(errors)}/{iterations}",
            elapsed_sec=elapsed,
        ))
        return passed

    def run(self) -> list[RobustnessResult]:
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
        }


def robustness_suite(tests: list[RobustnessTest]) -> dict[str, Any]:
    """运行一组鲁棒性测试并返回汇总"""
    all_results = []
    for test in tests:
        try:
            with timed(f"robustness.{test.name}"):
                test.run()
            all_results.extend(test.results)
        except Exception as e:
            all_results.append(RobustnessResult(
                test_name=f"{test.name}.setup",
                passed=False, module=test.module,
                scenario="setup", message=f"测试运行异常: {e}",
                exception=traceback.format_exc(),
            ))

    total = len(all_results)
    passed = sum(1 for r in all_results if r.passed)
    return {
        "total": total,
        "passed": passed,
        "failed": total - passed,
        "pass_rate": round(passed / total, 4) if total else 0,
        "by_module": _group_by_module(all_results),
        "details": all_results,
    }


def _group_by_module(results: list[RobustnessResult]) -> dict:
    by_module: dict[str, list[RobustnessResult]] = {}
    for r in results:
        by_module.setdefault(r.module or "unknown", []).append(r)
    return {
        mod: {
            "total": len(rs),
            "passed": sum(1 for r in rs if r.passed),
            "pass_rate": round(sum(1 for r in rs if r.passed) / len(rs), 4) if rs else 0,
        }
        for mod, rs in by_module.items()
    }
