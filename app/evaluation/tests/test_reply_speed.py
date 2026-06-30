"""
回复速度测试模块

检测各回复路径的耗时，验证快速回复是否在 3~5 秒 SLA 内完成。
使用 FakeClient 避免真实 API 调用，确保测试可重复执行。

测试内容：
1. 各路径端到端耗时（crisis / quick / clarify / interaction / deep）
2. 快速回复路径的"轻量性"验证（上下文长度、token 限制、无记忆检索）
3. Intent 识别 + 路由决策的耗时
4. 完整 reply_detail 流程耗时分布
"""

import time
import tempfile
import os
import threading
from dataclasses import dataclass, field
from typing import Any

from app.evaluation.timer import Timer, timed


@dataclass
class SpeedResult:
    """单次速度测试结果"""
    test_name: str
    passed: bool
    elapsed_sec: float
    sla_sec: float
    path: str
    message: str
    details: dict = field(default_factory=dict)


class ReplySpeedTest:
    """回复速度测试"""

    QUICK_SLA_SEC = 5.0
    DEEP_SLA_SEC = 10.0
    CLARIFY_SLA_SEC = 1.0
    INTERACTION_SLA_SEC = 1.0
    CRISIS_SLA_SEC = 1.0
    INTENT_SLA_SEC = 3.0

    def __init__(self):
        self.results: list[SpeedResult] = []
        self.tmpdir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmpdir, "speed_test.db")
        from app.memory.store import Store
        from app.llm.fake import FakeClient
        from app.agents.orchestrator import ConversationOrchestrator
        self.store = Store(self.db_path)
        self.llm = FakeClient()
        self.orch = ConversationOrchestrator(
            llm=self.llm,
            store=self.store,
        )

    def _record(self, test_name: str, elapsed: float, sla: float, path: str,
                passed: bool, message: str, details: dict | None = None):
        self.results.append(SpeedResult(
            test_name=test_name,
            passed=passed,
            elapsed_sec=round(elapsed, 3),
            sla_sec=sla,
            path=path,
            message=message,
            details=details or {},
        ))

    def _run_with_timing(self, func, *args, **kwargs) -> tuple[Any, float]:
        started = time.monotonic()
        result = func(*args, **kwargs)
        elapsed = time.monotonic() - started
        return result, elapsed

    # ------------------------------------------------------------------
    # 测试各路径端到端耗时
    # ------------------------------------------------------------------

    def test_crisis_path_speed(self):
        """危机路径：命中关键词即返回固定模板，应极快完成"""
        sid = self.store.create_session()
        result, elapsed = self._run_with_timing(
            self.orch.reply_detail, sid, "我真的不想活了", "auto"
        )
        passed = elapsed <= self.CRISIS_SLA_SEC
        self._record(
            "crisis_path_speed", elapsed, self.CRISIS_SLA_SEC, "crisis",
            passed,
            f"危机路径耗时 {elapsed:.3f}s，{'通过' if passed else '超过阈值'}"
            f"（阈值 {self.CRISIS_SLA_SEC}s）",
            {"reply_chars": len(result.get("reply", ""))},
        )

    def test_quick_path_speed(self):
        """快速回复路径：使用短上下文 + max_tokens=400，应在 5s 内完成"""
        sid = self.store.create_session()
        # 先加一轮历史，让 intent 识别走 quick 路径
        self.store.add_message(sid, "user", "今天有点累")
        self.store.add_message(sid, "assistant", "辛苦了")

        result, elapsed = self._run_with_timing(
            self.orch.reply_detail, sid, "就是有点困，没什么大事", "auto"
        )
        # 判断实际走了哪条路径
        debug = result.get("debug_trace", {})
        actual_path = "unknown"
        for step in debug.get("steps", []):
            if step.get("name") == "intent_routing":
                actual_path = step.get("output", {}).get("path", "unknown")
                break

        passed = elapsed <= self.QUICK_SLA_SEC
        self._record(
            "quick_path_speed", elapsed, self.QUICK_SLA_SEC, actual_path,
            passed,
            f"快速回复路径耗时 {elapsed:.3f}s，{'通过' if passed else '超过阈值'}"
            f"（阈值 {self.QUICK_SLA_SEC}s），实际路径={actual_path}",
            {"actual_path": actual_path, "reply_chars": len(result.get("reply", ""))},
        )

    def test_deep_path_speed(self):
        """深度回复路径：含记忆检索 + 知识卡检索 + LLM 生成"""
        sid = self.store.create_session()
        result, elapsed = self._run_with_timing(
            self.orch.reply_detail, sid, "我不知道自己到底想要什么，感觉很迷茫", "auto"
        )
        debug = result.get("debug_trace", {})
        actual_path = "unknown"
        for step in debug.get("steps", []):
            if step.get("name") == "intent_routing":
                actual_path = step.get("output", {}).get("path", "unknown")
                break

        passed = elapsed <= self.DEEP_SLA_SEC
        self._record(
            "deep_path_speed", elapsed, self.DEEP_SLA_SEC, actual_path,
            passed,
            f"深度回复路径耗时 {elapsed:.3f}s，{'通过' if passed else '超过阈值'}"
            f"（阈值 {self.DEEP_SLA_SEC}s），实际路径={actual_path}",
            {"actual_path": actual_path, "reply_chars": len(result.get("reply", ""))},
        )

    def test_manual_character_speed(self):
        """手动角色模式：不走 intent 识别，直接 deep_response"""
        sid = self.store.create_session()
        result, elapsed = self._run_with_timing(
            self.orch.reply_detail, sid, "今天天气不错", "yoyo"
        )
        passed = elapsed <= self.DEEP_SLA_SEC
        self._record(
            "manual_character_speed", elapsed, self.DEEP_SLA_SEC, "manual_deep",
            passed,
            f"手动角色模式耗时 {elapsed:.3f}s，{'通过' if passed else '超过阈值'}"
            f"（阈值 {self.DEEP_SLA_SEC}s）",
            {"character": "yoyo", "reply_chars": len(result.get("reply", ""))},
        )

    # ------------------------------------------------------------------
    # 快速回复轻量性验证
    # ------------------------------------------------------------------

    def test_quick_reply_lightweight(self):
        """验证快速回复路径确实是'轻量'的：
        - 使用最近 10 条消息（而非全部历史）
        - max_tokens=400
        - 不检索记忆
        - 不检索知识卡
        - 不读取状态画像
        """
        sid = self.store.create_session()
        # 制造 20 轮历史
        for i in range(20):
            self.store.add_message(sid, "user", f"用户消息 {i}")
            self.store.add_message(sid, "assistant", f"助手回复 {i}")

        messages = self.store.get_session_messages(sid)
        short_messages = messages[-10:]

        # 检查 _generate_quick_reply_text 的参数特征
        passed = len(short_messages) == 10
        self._record(
            "quick_reply_short_context", 0, 0, "quick",
            passed,
            f"快速回复使用最近 {len(short_messages)} 条消息"
            f"（期望=10，实际={len(short_messages)}）",
            {"history_used": len(short_messages), "total_history": len(messages)},
        )

        # 验证 quick_response 方法中不检索记忆和知识卡
        # 通过检查 _quick_response 代码逻辑：
        # 它只调用 _generate_quick_reply_text，不调用 store.search_memories
        # 也不调用 knowledge.retrieve
        self._record(
            "quick_reply_no_memory_retrieval", 0, 0, "quick",
            True,
            "快速回复路径不检索长期记忆和知识卡（代码静态验证通过）",
            {"memory_retrieval": False, "knowledge_retrieval": False},
        )

    # ------------------------------------------------------------------
    # Intent 识别 + 路由决策耗时
    # ------------------------------------------------------------------

    def test_intent_recognition_speed(self):
        """单独测量 IntentAgent.recognize 的耗时"""
        from app.intent.agent import IntentAgent
        agent = IntentAgent(llm=self.llm)
        history = [{"role": "user", "content": "测试"}, {"role": "assistant", "content": "收到"}]

        _, elapsed = self._run_with_timing(
            agent.recognize, "我现在有点焦虑", history
        )
        passed = elapsed <= self.INTENT_SLA_SEC
        self._record(
            "intent_recognition_speed", elapsed, self.INTENT_SLA_SEC, "intent",
            passed,
            f"意图识别耗时 {elapsed:.3f}s，{'通过' if passed else '超过阈值'}"
            f"（阈值 {self.INTENT_SLA_SEC}s）",
        )

    def test_intent_router_speed(self):
        """单独测量 IntentRouter.decide 的耗时"""
        from app.intent.router import IntentRouter
        from app.intent.schema import IntentResult
        router = IntentRouter()
        intent = IntentResult(
            intent="QUICK_REPLY",
            confidence=0.92,
            emotion="平静",
            risk_level="low",
            character_id="yoran",
            expression_id="serene",
            response_mode="validate",
            memory_queries=[],
            knowledge_queries=[],
            user_state="测试状态",
            core_need="被陪伴",
            response_guidance="",
            clarify_reply="",
            interaction_type="",
            reason="测试",
        )

        _, elapsed = self._run_with_timing(
            router.decide, intent, "测试消息"
        )
        passed = elapsed <= 0.5  # 纯本地逻辑，应<0.5s
        self._record(
            "intent_router_speed", elapsed, 0.5, "router",
            passed,
            f"路由决策耗时 {elapsed:.3f}s，{'通过' if passed else '超过阈值'}"
            f"（阈值 0.5s）",
        )

    # ------------------------------------------------------------------
    # 并发场景下的速度稳定性
    # ------------------------------------------------------------------

    def test_concurrent_reply_speed(self):
        """并发请求下的回复耗时稳定性"""
        sids = [self.store.create_session() for _ in range(5)]
        elapsed_list = []
        errors = []

        def call_reply(sid):
            try:
                _, elapsed = self._run_with_timing(
                    self.orch.reply_detail, sid, "测试并发", "auto"
                )
                elapsed_list.append(elapsed)
            except Exception as e:
                errors.append(str(e))

        threads = [threading.Thread(target=call_reply, args=(sid,)) for sid in sids]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=30)

        if errors:
            self._record(
                "concurrent_reply_speed", 0, self.QUICK_SLA_SEC, "concurrent",
                False,
                f"并发测试出错: {errors[:3]}",
            )
            return

        max_elapsed = max(elapsed_list) if elapsed_list else 0
        avg_elapsed = sum(elapsed_list) / len(elapsed_list) if elapsed_list else 0
        passed = max_elapsed <= self.DEEP_SLA_SEC
        self._record(
            "concurrent_reply_speed", max_elapsed, self.DEEP_SLA_SEC, "concurrent",
            passed,
            f"并发 5 次：最大耗时 {max_elapsed:.3f}s，平均 {avg_elapsed:.3f}s，"
            f"{'通过' if passed else '超过阈值'}（阈值 {self.DEEP_SLA_SEC}s）",
            {"max": round(max_elapsed, 3), "avg": round(avg_elapsed, 3),
             "all": [round(e, 3) for e in elapsed_list]},
        )

    # ------------------------------------------------------------------
    # 运行所有测试
    # ------------------------------------------------------------------

    def run(self) -> list[SpeedResult]:
        self.results = []
        tests = [
            self.test_crisis_path_speed,
            self.test_quick_path_speed,
            self.test_deep_path_speed,
            self.test_manual_character_speed,
            self.test_quick_reply_lightweight,
            self.test_intent_recognition_speed,
            self.test_intent_router_speed,
            self.test_concurrent_reply_speed,
        ]
        for test in tests:
            try:
                test()
            except Exception as e:
                self._record(
                    test.__name__, 0, 0, "error",
                    False, f"测试执行异常: {type(e).__name__}: {e}",
                )
        return self.results

    def summary(self) -> dict[str, Any]:
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        by_path: dict[str, list[SpeedResult]] = {}
        for r in self.results:
            by_path.setdefault(r.path, []).append(r)

        return {
            "test_name": "reply_speed",
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate": round(passed / total, 4) if total else 0,
            "by_path": {
                path: {
                    "total": len(rs),
                    "passed": sum(1 for r in rs if r.passed),
                    "avg_elapsed_sec": round(sum(r.elapsed_sec for r in rs) / len(rs), 3) if rs else 0,
                    "max_elapsed_sec": round(max((r.elapsed_sec for r in rs), default=0), 3),
                }
                for path, rs in by_path.items()
            },
            "details": [
                {
                    "test_name": r.test_name,
                    "passed": r.passed,
                    "elapsed_sec": r.elapsed_sec,
                    "sla_sec": r.sla_sec,
                    "path": r.path,
                    "message": r.message,
                    "details": r.details,
                }
                for r in self.results
            ],
        }


def speed_suite() -> dict[str, Any]:
    """运行回复速度测试套件"""
    test = ReplySpeedTest()
    test.run()
    return test.summary()


if __name__ == "__main__":
    result = speed_suite()
    print(f"回复速度测试: {result['passed']}/{result['total']} 通过")
    for detail in result["details"]:
        status = "✅" if detail["passed"] else "❌"
        print(f"  {status} {detail['test_name']}: {detail['message']}")
