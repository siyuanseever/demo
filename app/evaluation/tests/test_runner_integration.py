"""
Runner 集成测试

端到端验证 EvaluationRunner 能否正确生成报告文件。
"""

import tempfile
import json
import os

from app.evaluation.accuracy import AccuracyTest


class RunnerIntegrationAccuracyTest(AccuracyTest):
    """runner 集成测试"""

    def __init__(self):
        super().__init__("runner_integration", "evaluation.runner")

    def run(self):
        from app.evaluation.runner import EvaluationRunner

        with tempfile.TemporaryDirectory() as tmpdir:
            runner = EvaluationRunner(tmpdir, output_dir=tmpdir)
            result = runner.run_all()

            # 1. 结果结构完整性
            self.assert_true("result_has_overall", "overall" in result)
            self.assert_true("result_has_timer", "timer_summary" in result)
            self.assert_true("result_has_accuracy", "accuracy" in result)
            self.assert_true("result_has_robustness", "robustness" in result)
            self.assert_true("result_has_completeness", "completeness" in result)

            # 2. overall 字段
            overall = result["overall"]
            self.assert_true("overall_has_total_tests", "total_tests" in overall)
            self.assert_true("overall_has_passed", "total_passed" in overall)
            self.assert_true("overall_has_failed", "total_failed" in overall)
            self.assert_true("overall_has_pass_rate", "overall_pass_rate" in overall)
            self.assert_true("overall_total_gte_0", overall.get("total_tests", -1) >= 0)

            # 3. 报告文件生成
            json_files = [f for f in os.listdir(tmpdir) if f.endswith(".json")]
            html_files = [f for f in os.listdir(tmpdir) if f.endswith(".html")]
            self.assert_true("json_report_generated", len(json_files) >= 1, "应生成 JSON 报告")
            self.assert_true("html_report_generated", len(html_files) >= 1, "应生成 HTML 报告")

            # 4. JSON 报告内容验证
            if json_files:
                json_path = os.path.join(tmpdir, json_files[0])
                with open(json_path, "r", encoding="utf-8") as f:
                    report_data = json.load(f)
                self.assert_true("report_has_generated_at", "generated_at" in report_data)
                self.assert_true("report_has_project_root", "project_root" in report_data)
                self.assert_true("report_overall_structure", "overall" in report_data)

        return self.results


def get_runner_integration_tests() -> list[AccuracyTest]:
    """返回 Runner 集成测试实例"""
    return [RunnerIntegrationAccuracyTest()]
