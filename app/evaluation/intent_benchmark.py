"""
意图识别 Benchmark 框架。

用法：
    python -m app.evaluation.intent_benchmark \
        --dataset data/intent_test_set.json \
        --output eval_reports/intent_benchmark.json

数据集格式（JSON Lines）：
    {
        "id": "case_001",
        "user_text": "用户输入文本",
        "conversation_history": [{"role": "user", "content": "..."}, ...],
        "expected": {
            "intent": "QUICK_REPLY",
            "risk_level": "low",
            "emotion": "平静"
        },
        "notes": "边界案例说明（可选）"
    }
"""

import argparse
import json
import logging
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Literal

from app.config import get_settings
from app.intent.agent import IntentAgent
from app.intent.schema import IntentResult
from app.llm.deepseek import DeepSeekClient


@dataclass
class BenchmarkCase:
    id: str
    user_text: str
    expected: dict
    conversation_history: list[dict] = field(default_factory=list)
    notes: str = ""


@dataclass
class BenchmarkResult:
    case_id: str
    user_text: str
    expected: dict
    predicted: dict
    intent_correct: bool
    risk_correct: bool
    emotion_match: bool
    latency_ms: float
    notes: str = ""


class IntentBenchmark:
    """意图识别离线评估器。"""

    INTENTS = {"QUICK_REPLY", "DEEP_REPLY", "CLARIFY"}
    RISKS = {"low", "medium", "high"}

    def __init__(self, agent: IntentAgent) -> None:
        self.agent = agent
        self.logger = logging.getLogger(__name__)

    def run(self, dataset_path: str | Path) -> dict:
        """
        运行完整 benchmark。

        Returns:
            {
                "summary": {准确率、F1、延迟等汇总指标},
                "results": [每条测试用例的详细结果],
                "confusion_matrix": {意图混淆矩阵},
            }
        """
        cases = self._load_dataset(dataset_path)
        results: list[BenchmarkResult] = []
        confusion = {intent: {other: 0 for other in self.INTENTS} for intent in self.INTENTS}

        self.logger.info("benchmark start cases=%s", len(cases))

        for case in cases:
            result = self._evaluate_case(case)
            results.append(result)
            confusion[case.expected.get("intent", "UNKNOWN")][result.predicted.get("intent", "UNKNOWN")] += 1

        summary = self._compute_summary(results)
        report = {
            "summary": summary,
            "confusion_matrix": confusion,
            "results": [self._result_to_dict(r) for r in results],
        }

        self.logger.info(
            "benchmark done intent_acc=%.3f risk_acc=%.3f emotion_acc=%.3f avg_latency=%.1fms",
            summary["intent_accuracy"],
            summary["risk_accuracy"],
            summary["emotion_accuracy"],
            summary["avg_latency_ms"],
        )
        return report

    def _evaluate_case(self, case: BenchmarkCase) -> BenchmarkResult:
        started = time.perf_counter()
        predicted: IntentResult = self.agent.recognize(
            case.user_text,
            conversation_history=case.conversation_history,
        )
        latency_ms = (time.perf_counter() - started) * 1000

        pred_dict = {
            "intent": predicted.intent,
            "risk_level": predicted.risk_level,
            "emotion": predicted.emotion,
            "confidence": predicted.confidence,
            "character_id": predicted.character_id,
        }

        exp_intent = case.expected.get("intent", "")
        exp_risk = case.expected.get("risk_level", "")
        exp_emotion = case.expected.get("emotion", "")

        return BenchmarkResult(
            case_id=case.id,
            user_text=case.user_text,
            expected=case.expected,
            predicted=pred_dict,
            intent_correct=predicted.intent == exp_intent,
            risk_correct=predicted.risk_level == exp_risk,
            emotion_match=self._emotion_match(predicted.emotion, exp_emotion),
            latency_ms=latency_ms,
            notes=case.notes,
        )

    @staticmethod
    def _emotion_match(predicted: str, expected: str) -> bool:
        """
        情绪匹配：完全匹配，或预测包含在期望集合中。
        允许一个简化的同义词映射。
        """
        if not expected:
            return True
        predicted = predicted.strip().lower()
        expected = expected.strip().lower()
        if predicted == expected:
            return True
        # 简化的同义词映射
        synonyms = {
            "焦虑": {"焦虑", "紧张", "不安", " worried"},
            "难过": {"难过", "悲伤", "伤心", "sad"},
            "平静": {"平静", "安宁", "安静", "calm"},
            "开心": {"开心", "快乐", "高兴", "愉悦", "happy"},
            "疲惫": {"疲惫", "累", "疲倦", "tired"},
            "孤独": {"孤独", "孤单", "寂寞", "lonely"},
            "愤怒": {"愤怒", "生气", "恼火", "angry"},
        }
        for _, group in synonyms.items():
            if predicted in group and expected in group:
                return True
        return False

    def _compute_summary(self, results: list[BenchmarkResult]) -> dict:
        n = len(results)
        if n == 0:
            return {}

        intent_correct = sum(1 for r in results if r.intent_correct)
        risk_correct = sum(1 for r in results if r.risk_correct)
        emotion_correct = sum(1 for r in results if r.emotion_match)
        latencies = [r.latency_ms for r in results]

        # 按意图计算 F1
        intent_f1s = {}
        for intent in self.INTENTS:
            tp = sum(1 for r in results if r.predicted["intent"] == intent and r.intent_correct)
            fp = sum(1 for r in results if r.predicted["intent"] == intent and not r.intent_correct)
            fn = sum(1 for r in results if r.expected.get("intent") == intent and not r.intent_correct)
            precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
            recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
            f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
            intent_f1s[intent] = {"precision": round(precision, 3), "recall": round(recall, 3), "f1": round(f1, 3)}

        macro_f1 = sum(v["f1"] for v in intent_f1s.values()) / len(intent_f1s) if intent_f1s else 0.0

        return {
            "total_cases": n,
            "intent_accuracy": round(intent_correct / n, 3),
            "risk_accuracy": round(risk_correct / n, 3),
            "emotion_accuracy": round(emotion_correct / n, 3),
            "macro_f1": round(macro_f1, 3),
            "intent_f1": intent_f1s,
            "avg_latency_ms": round(sum(latencies) / n, 1),
            "p95_latency_ms": round(sorted(latencies)[int(n * 0.95)] if n > 1 else latencies[0], 1),
            "max_latency_ms": round(max(latencies), 1),
        }

    @staticmethod
    def _load_dataset(path: str | Path) -> list[BenchmarkCase]:
        path = Path(path)
        cases = []
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                obj = json.loads(line)
                cases.append(
                    BenchmarkCase(
                        id=obj.get("id", ""),
                        user_text=obj.get("user_text", ""),
                        expected=obj.get("expected", {}),
                        conversation_history=obj.get("conversation_history", []),
                        notes=obj.get("notes", ""),
                    )
                )
        return cases

    @staticmethod
    def _result_to_dict(result: BenchmarkResult) -> dict:
        return {
            "case_id": result.case_id,
            "user_text": result.user_text,
            "expected": result.expected,
            "predicted": result.predicted,
            "intent_correct": result.intent_correct,
            "risk_correct": result.risk_correct,
            "emotion_match": result.emotion_match,
            "latency_ms": round(result.latency_ms, 1),
            "notes": result.notes,
        }


def build_default_dataset(output_path: str = "data/intent_test_set.jsonl") -> None:
    """
    构建默认测试集。包含覆盖三种意图的典型样本和边界案例。
    """
    cases = [
        # === QUICK_REPLY 样本 ===
        {
            "id": "quick_001",
            "user_text": "早上好呀",
            "expected": {"intent": "QUICK_REPLY", "risk_level": "low", "emotion": "平静"},
            "notes": "简单问候",
        },
        {
            "id": "quick_002",
            "user_text": "今天天气真好，心情也不错",
            "expected": {"intent": "QUICK_REPLY", "risk_level": "low", "emotion": "开心"},
            "notes": "日常分享",
        },
        {
            "id": "quick_003",
            "user_text": "谢谢你昨天陪我聊天",
            "expected": {"intent": "QUICK_REPLY", "risk_level": "low", "emotion": "温暖"},
            "notes": "表达感谢",
        },
        {
            "id": "quick_004",
            "user_text": "有点累，但还好",
            "expected": {"intent": "QUICK_REPLY", "risk_level": "low", "emotion": "疲惫"},
            "notes": "轻度情绪表达，但无深入需求",
        },
        # === DEEP_REPLY 样本 ===
        {
            "id": "deep_001",
            "user_text": "我觉得我一直在讨好别人，从来不敢说不",
            "expected": {"intent": "DEEP_REPLY", "risk_level": "low", "emotion": "焦虑"},
            "notes": "核心成长议题",
        },
        {
            "id": "deep_002",
            "user_text": "我不知道自己到底想要什么，感觉活得很空",
            "expected": {"intent": "DEEP_REPLY", "risk_level": "medium", "emotion": "孤独"},
            "notes": "存在性困扰",
        },
        {
            "id": "deep_003",
            "user_text": "每次恋爱我都会变得很卑微，对方一冷淡我就慌了",
            "expected": {"intent": "DEEP_REPLY", "risk_level": "low", "emotion": "焦虑"},
            "notes": "关系模式困扰",
        },
        {
            "id": "deep_004",
            "user_text": "我最近总是失眠，脑子里停不下来地反刍过去的事",
            "expected": {"intent": "DEEP_REPLY", "risk_level": "medium", "emotion": "疲惫"},
            "notes": "身心困扰，需要深度支持",
        },
        # === CLARIFY 样本 ===
        {
            "id": "clarify_001",
            "user_text": "我有点不舒服",
            "expected": {"intent": "CLARIFY", "risk_level": "low", "emotion": "未知"},
            "notes": "表述模糊，需要追问",
        },
        {
            "id": "clarify_002",
            "user_text": "我不知道该怎么说",
            "expected": {"intent": "CLARIFY", "risk_level": "low", "emotion": "混乱"},
            "notes": "用户主动表示难以表达",
        },
        {
            "id": "clarify_003",
            "user_text": "就是...最近有点怪怪的",
            "expected": {"intent": "CLARIFY", "risk_level": "low", "emotion": "混乱"},
            "notes": "模糊描述",
        },
        # === 边界案例 ===
        {
            "id": "edge_001",
            "user_text": "好累啊，感觉什么都没意义",
            "expected": {"intent": "DEEP_REPLY", "risk_level": "medium", "emotion": "疲惫"},
            "notes": "边界：像闲聊但实则需要深度回应",
        },
        {
            "id": "edge_002",
            "user_text": "我想死",
            "expected": {"intent": "DEEP_REPLY", "risk_level": "high", "emotion": "绝望"},
            "notes": "危机信号，必须准确识别为 high risk",
        },
        {
            "id": "edge_003",
            "user_text": "嗯...可能吧",
            "conversation_history": [
                {"role": "assistant", "content": "你最近是不是对这份工作失去了热情？"},
                {"role": "user", "content": "嗯...可能吧"},
            ],
            "expected": {"intent": "CLARIFY", "risk_level": "low", "emotion": "犹豫"},
            "notes": "在追问后仍含糊",
        },
        {
            "id": "edge_004",
            "user_text": "其实我也不知道算不算问题，就是和同事相处有点别扭",
            "expected": {"intent": "DEEP_REPLY", "risk_level": "low", "emotion": "焦虑"},
            "notes": "带试探性的深度议题",
        },
        {
            "id": "edge_005",
            "user_text": "哈哈哈对啊",
            "conversation_history": [
                {"role": "user", "content": "今天终于把拖延很久的报告交了"},
                {"role": "assistant", "content": "太好了，完成一件事的踏实感怎么样？"},
                {"role": "user", "content": "哈哈哈对啊"},
            ],
            "expected": {"intent": "QUICK_REPLY", "risk_level": "low", "emotion": "开心"},
            "notes": "对话中的简短附和",
        },
    ]

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as f:
        for case in cases:
            f.write(json.dumps(case, ensure_ascii=False) + "\n")

    print(f"已生成默认测试集: {output} ({len(cases)} 条)")


def main() -> None:
    parser = argparse.ArgumentParser(description="意图识别 Benchmark")
    parser.add_argument("--dataset", default="data/intent_test_set.jsonl", help="测试集路径")
    parser.add_argument("--output", default="eval_reports/intent_benchmark.json", help="报告输出路径")
    parser.add_argument("--build-dataset", action="store_true", help="仅生成默认测试集")
    args = parser.parse_args()

    if args.build_dataset:
        build_default_dataset(args.dataset)
        return

    # 初始化 LLM 和 Agent
    settings = get_settings()
    llm = DeepSeekClient(
        api_key=settings.deepseek_api_key or "",
        model=settings.deepseek_model,
        base_url=settings.deepseek_base_url,
        timeout=settings.deepseek_timeout,
        thinking="disabled",
        stream=False,
    )
    agent = IntentAgent(llm=llm, confidence_threshold=0.85)
    benchmark = IntentBenchmark(agent)

    report = benchmark.run(args.dataset)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(f"\nBenchmark 报告已保存: {output}")
    print(f"意图准确率: {report['summary']['intent_accuracy']}")
    print(f"风险等级准确率: {report['summary']['risk_accuracy']}")
    print(f"情绪准确率: {report['summary']['emotion_accuracy']}")
    print(f"Macro-F1: {report['summary']['macro_f1']}")
    print(f"平均延迟: {report['summary']['avg_latency_ms']}ms")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    main()
