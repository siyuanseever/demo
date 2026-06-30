"""
Layered checker runner for the local loop-engineering workflow.

The goal is not to replace human review. It gives a maker/checker loop a
deterministic first gate:
- contract: backend event/data persistence contracts
- ui: rendered browser script and UI-facing contracts
- quality: low-cost product behavior sanity checks

Run:
    python3 -m app.evaluation.check_loop
"""

from __future__ import annotations

import json
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable

from app.evaluation.check_sse_stream import (
    check_rendered_web_script,
    check_sse_deep_reply_contract,
    check_sse_quick_reply_contract,
)


@dataclass
class CheckResult:
    layer: str
    name: str
    passed: bool
    elapsed_sec: float
    error: str = ""


def run_check(layer: str, name: str, func: Callable[[], None]) -> CheckResult:
    started_at = time.monotonic()
    try:
        func()
        return CheckResult(layer=layer, name=name, passed=True, elapsed_sec=round(time.monotonic() - started_at, 3))
    except Exception as error:
        return CheckResult(
            layer=layer,
            name=name,
            passed=False,
            elapsed_sec=round(time.monotonic() - started_at, 3),
            error=str(error),
        )


def check_intent_route_quality() -> None:
    """Small deterministic quality guard for routing decisions."""
    from app.intent.router import IntentRouter
    from app.intent.schema import IntentResult

    router = IntentRouter(confidence_threshold=0.85)
    cases = [
        (
            "high risk overrides quick",
            IntentResult(
                intent="QUICK_REPLY",
                confidence=0.95,
                user_state="绝望",
                core_need="立刻获得安全支持",
                emotion="绝望",
                risk_level="high",
            ),
            "随便说说",
            "crisis",
        ),
        (
            "clarify stays clarify",
            IntentResult(
                intent="CLARIFY",
                confidence=0.45,
                user_state="表达模糊",
                core_need="被温柔追问",
                emotion="混乱",
                risk_level="low",
                clarify_reply="你愿意先告诉我，这种不舒服更像身体累，还是心里堵吗？",
            ),
            "有点怪",
            "clarify",
        ),
        (
            "deep low confidence uses thinking",
            IntentResult(
                intent="DEEP_REPLY",
                confidence=0.3,
                user_state="线索不足",
                core_need="重新判断意图",
                emotion="未知",
                risk_level="low",
            ),
            "我也不知道",
            "deep",
        ),
        (
            "deep validate normalizes to mixed",
            IntentResult(
                intent="DEEP_REPLY",
                confidence=0.92,
                user_state="想理解内在模式",
                core_need="获得深入理解",
                emotion="困惑",
                risk_level="low",
                response_mode="validate",
            ),
            "我想知道自己为什么总是这样",
            "deep",
        ),
        (
            "interaction routes interaction",
            IntentResult(
                intent="INTERACTION",
                confidence=0.92,
                user_state="想做练习",
                core_need="身体稳定",
                emotion="焦虑",
                risk_level="low",
                interaction_type="breathing",
            ),
            "陪我做呼吸",
            "interaction",
        ),
    ]
    for label, intent, user_text, expected_path in cases:
        result = router.decide(intent, user_text)
        if result.path != expected_path:
            raise AssertionError(f"{label}: expected {expected_path}, got {result.path}")
    low_conf_result = router.decide(cases[2][1], cases[2][2])
    if not low_conf_result.use_thinking:
        raise AssertionError("low-confidence deep reply must request thinking fallback")
    normalized_result = router.decide(cases[3][1], cases[3][2])
    if normalized_result.route_plan and normalized_result.route_plan.get("response_mode") != "mixed":
        raise AssertionError("high-confidence deep validate mode must normalize to mixed")


def run_all() -> dict:
    checks: list[tuple[str, str, Callable[[], None]]] = [
        ("contract", "sse_deep_reply_contract", check_sse_deep_reply_contract),
        ("contract", "sse_quick_reply_contract", check_sse_quick_reply_contract),
        ("ui", "rendered_web_script", check_rendered_web_script),
        ("quality", "intent_route_quality", check_intent_route_quality),
    ]
    results = [run_check(layer, name, func) for layer, name, func in checks]
    passed = sum(1 for result in results if result.passed)
    total = len(results)
    confidence = round(passed / total, 3) if total else 0.0
    return {
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total": total,
        "passed": passed,
        "failed": total - passed,
        "confidence": confidence,
        "merge_recommendation": "auto_merge_candidate" if confidence == 1.0 else "needs_human_review",
        "results": [asdict(result) for result in results],
    }


def main() -> None:
    report = run_all()
    output_dir = Path("eval_reports")
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"loop_check_{int(time.time())}.json"
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    for result in report["results"]:
        status = "PASS" if result["passed"] else "FAIL"
        print(f"{status} [{result['layer']}] {result['name']} ({result['elapsed_sec']}s)")
        if result["error"]:
            print(f"  {result['error']}")
    print(
        f"confidence={report['confidence']:.3f} "
        f"recommendation={report['merge_recommendation']} "
        f"report={output_path}"
    )
    if report["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
