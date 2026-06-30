"""
评估主运行器

一键运行所有维度的评估，并生成报告。

使用方法:
    python3 -m app.evaluation.runner

自定义输出目录:
    python3 -m app.evaluation.runner --output-dir ./my_reports
"""

import time
import argparse
import traceback
from pathlib import Path
from typing import Any

from app.evaluation.timer import Timer, timed
from app.evaluation.metrics import MetricsCollector
from app.evaluation.accuracy import accuracy_suite
from app.evaluation.robustness import robustness_suite
from app.evaluation.completeness import CompletenessChecker
from app.evaluation.reporter import ReportGenerator


def _run_timer_benchmarks() -> list[dict]:
    """运行耗时基准测试"""
    from app.evaluation.tests.benchmarks import run_all_benchmarks
    return run_all_benchmarks()


def _run_accuracy_tests() -> dict[str, Any]:
    """运行准确率测试"""
    from app.evaluation.tests.test_accuracy import get_accuracy_tests
    tests = get_accuracy_tests()
    return accuracy_suite(tests)


def _run_robustness_tests() -> dict[str, Any]:
    """运行鲁棒性测试"""
    from app.evaluation.tests.test_robustness import get_robustness_tests
    tests = get_robustness_tests()
    return robustness_suite(tests)


def _run_completeness_checks(project_root: str) -> dict[str, Any]:
    """运行完整性检查"""
    checker = CompletenessChecker(project_root)

    # 关键文件存在性
    checker.check_file_exists("app/llm/deepseek.py", "DeepSeek LLM 适配器")
    checker.check_file_exists("app/llm/base.py", "LLM 基类")
    checker.check_file_exists("app/agents/orchestrator.py", "对话编排器")
    checker.check_file_exists("app/agents/safety.py", "安全模块")
    checker.check_file_exists("app/memory/store.py", "数据存储")
    checker.check_file_exists("app/memory/schema.py", "数据库 Schema")
    checker.check_file_exists("app/knowledge/retriever.py", "知识检索")
    checker.check_file_exists("app/web.py", "Web UI")
    checker.check_file_exists("app/characters.py", "角色定义")
    checker.check_file_exists("app/config.py", "配置模块")
    checker.check_file_exists("app/evaluation/cases/cases.yaml", "评估用例")
    checker.check_file_exists("app/evaluation/cases/rubric.md", "评分标准")

    # 模块可导入性
    checker.check_module_importable("app.llm.deepseek")
    checker.check_module_importable("app.agents.orchestrator")
    checker.check_module_importable("app.memory.store")
    checker.check_module_importable("app.knowledge.retriever")

    # AST 定义检查
    checker.check_ast_definitions(
        "app/llm/deepseek.py",
        expected_functions=["_read_stream"],
        expected_classes=["DeepSeekClient"],
    )
    checker.check_ast_definitions(
        "app/memory/store.py",
        expected_classes=["Store"],
    )
    checker.check_ast_definitions(
        "app/agents/orchestrator.py",
        expected_classes=["ConversationOrchestrator"],
    )

    # 依赖检查
    checker.check_dependencies("app.memory.store", ["sqlite3", "json", "os"])
    checker.check_dependencies("app.llm.deepseek", ["json", "urllib.request", "socket"])

    return checker.summary()


class EvaluationRunner:
    """评估运行器"""

    def __init__(self, project_root: str, output_dir: str = "eval_reports"):
        self.project_root = project_root
        self.output_dir = output_dir
        self.timer = Timer()
        self.metrics = MetricsCollector()
        self.reporter = ReportGenerator(output_dir)

    def run_all(self) -> dict[str, Any]:
        """运行所有评估并返回汇总数据"""
        started_at = time.monotonic()
        self.timer.reset()
        self.metrics.reset()

        print("=" * 60)
        print("🧪 项目评估开始")
        print("=" * 60)

        # 1. 耗时基准测试
        print("\n[1/5] ⏱  耗时评估...")
        try:
            timer_summary = _run_timer_benchmarks()
            print(f"   完成, 记录了 {len(timer_summary)} 个模块的耗时数据")
        except Exception as e:
            print(f"   错误: {e}")
            timer_summary = []

        # 2. 性能指标采集
        print("\n[2/5] 📊 性能指标采集...")
        try:
            self.metrics.record_memory()
            self.metrics.record_cpu()
            print(f"   RSS内存: {self.metrics._gauges.get('process_memory_rss_mb', 0):.1f} MB")
        except Exception as e:
            print(f"   错误: {e}")

        # 3. 准确率测试
        print("\n[3/5] ✅ 准确率评估...")
        try:
            accuracy_result = _run_accuracy_tests()
            print(f"   通过: {accuracy_result.get('passed', 0)}/{accuracy_result.get('total', 0)}")
        except Exception as e:
            print(f"   错误: {e}")
            accuracy_result = {"total": 0, "passed": 0, "failed": 0, "pass_rate": 0}

        # 4. 鲁棒性测试
        print("\n[4/5] 🛡 鲁棒性评估...")
        try:
            robustness_result = _run_robustness_tests()
            print(f"   通过: {robustness_result.get('passed', 0)}/{robustness_result.get('total', 0)}")
        except Exception as e:
            print(f"   错误: {e}")
            robustness_result = {"total": 0, "passed": 0, "failed": 0, "pass_rate": 0}

        # 5. 完整性检查
        print("\n[5/5] 📦 完整性评估...")
        try:
            completeness_result = _run_completeness_checks(self.project_root)
            print(f"   通过: {completeness_result.get('passed', 0)}/{completeness_result.get('total', 0)}")
        except Exception as e:
            print(f"   错误: {e}")
            completeness_result = {"total": 0, "passed": 0, "failed": 0, "pass_rate": 0}

        elapsed = time.monotonic() - started_at

        # 将 dataclass 对象转为 dict，确保 JSON 可序列化
        def _to_dict(obj):
            if hasattr(obj, "__dataclass_fields__"):
                return {k: _to_dict(v) for k, v in obj.__dict__.items()}
            if isinstance(obj, list):
                return [_to_dict(item) for item in obj]
            if isinstance(obj, dict):
                return {k: _to_dict(v) for k, v in obj.items()}
            return obj

        accuracy_result = _to_dict(accuracy_result)
        robustness_result = _to_dict(robustness_result)
        completeness_result = _to_dict(completeness_result)

        total_tests = (
            accuracy_result.get("total", 0)
            + robustness_result.get("total", 0)
            + completeness_result.get("total", 0)
        )
        total_passed = (
            accuracy_result.get("passed", 0)
            + robustness_result.get("passed", 0)
            + completeness_result.get("passed", 0)
        )
        total_failed = total_tests - total_passed
        overall_pass_rate = total_passed / total_tests if total_tests else 0

        report_data = {
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "project_root": self.project_root,
            "overall": {
                "total_tests": total_tests,
                "total_passed": total_passed,
                "total_failed": total_failed,
                "elapsed_sec": round(elapsed, 2),
                "overall_pass_rate": round(overall_pass_rate, 4),
            },
            "timer_summary": timer_summary,
            "metrics_summary": self.metrics.summary(),
            "accuracy": accuracy_result,
            "robustness": robustness_result,
            "completeness": completeness_result,
        }

        # 生成报告
        json_path = self.reporter.save_json(report_data)
        html_path = self.reporter.save_html(report_data)

        print("\n" + "=" * 60)
        print("📊 评估结果汇总")
        print("=" * 60)
        print(f"   总测试数: {total_tests}")
        print(f"   通过: {total_passed} | 失败: {total_failed}")
        print(f"   综合通过率: {overall_pass_rate*100:.1f}%")
        print(f"   总耗时: {elapsed:.2f}s")
        print(f"\n📁 报告已生成:")
        print(f"   JSON: {json_path}")
        print(f"   HTML: {html_path}")
        print("=" * 60)

        return report_data


def main():
    parser = argparse.ArgumentParser(description="CodeX 项目评估工具")
    parser.add_argument("--project-root", default=".", help="项目根目录")
    parser.add_argument("--output-dir", default="eval_reports", help="报告输出目录")
    args = parser.parse_args()

    project_root = str(Path(args.project_root).resolve())
    runner = EvaluationRunner(project_root, output_dir=args.output_dir)
    runner.run_all()


if __name__ == "__main__":
    main()
