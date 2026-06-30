"""
手工体验评估入口

基于 cases.yaml 中的用例，运行真实对话流程并输出结构化评分结果。

使用方法:
    python3 -m app.evaluation.manual_eval

输出:
    eval_reports/manual_eval_{timestamp}.json
"""

import json
import time
from pathlib import Path
from typing import Any

from app.evaluation.cases import load_yaml_cases, load_rubric


class ManualEvaluator:
    """手工体验评估器"""

    def __init__(self, output_dir: str = "eval_reports"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.cases = load_yaml_cases()
        self.rubric = load_rubric()

    def run_all_cases(self) -> dict[str, Any]:
        """运行所有用例并返回评估结果"""
        results = []

        for case in self.cases:
            case_result = self._run_single_case(case)
            results.append(case_result)

        report = {
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "eval_type": "manual_experience",
            "total_cases": len(results),
            "cases": results,
            "rubric": self.rubric,
        }

        # 保存报告
        timestamp = int(time.time())
        path = self.output_dir / f"manual_eval_{timestamp}.json"
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"📁 手工评估报告已保存: {path}")

        return report

    def _run_single_case(self, case: dict[str, Any]) -> dict[str, Any]:
        """运行单个用例"""
        case_id = case.get("id", "unknown")
        title = case.get("title", "")
        user_input = case.get("user", "")

        print(f"\n📝 用例 [{case_id}]: {title}")
        print(f"   用户输入: {user_input[:60]}{'...' if len(user_input) > 60 else ''}")

        # 当前为半自动模式：收集用户输入，模拟对话流程
        # 实际运行时由人工评分，此处输出结构供后续扩展为自动调用
        return {
            "case_id": case_id,
            "title": title,
            "user_input": user_input,
            "status": "pending_manual_review",
            "scores": {},
            "failure_types": [],
            "notes": "请在真实对话后手工评分",
        }

    def print_rubric(self) -> None:
        """打印评分标准"""
        print("=" * 60)
        print("📋 对话体验评分标准")
        print("=" * 60)
        for dim in self.rubric.get("dimensions", []):
            name = dim.get("name", "")
            scale = dim.get("scale", "")
            print(f"  • {name}：{scale}")
        print("\n失败类型记录：")
        for ft in self.rubric.get("failure_types", []):
            print(f"  • {ft}")
        print("=" * 60)


def main():
    evaluator = ManualEvaluator()

    if not evaluator.cases:
        print("⚠️ 未找到评估用例，请确认 app/evaluation/cases/cases.yaml 存在")
        return

    evaluator.print_rubric()
    print(f"\n🧪 共 {len(evaluator.cases)} 个用例待评估")
    print("当前为半自动模式：输出结构化报告，实际评分需在真实对话后手工完成。\n")

    report = evaluator.run_all_cases()
    print(f"\n✅ 评估完成，共 {report['total_cases']} 个用例")


if __name__ == "__main__":
    main()
