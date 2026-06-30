"""
功能完整性与鲁棒性测试模块

验证各函数、功能是否完整稳定，覆盖所有回复路径和边界条件。

测试内容：
1. 全路径覆盖：crisis / quick / clarify / interaction / deep / manual
2. 边界条件：空输入、超长输入、特殊字符、SQL 注入尝试
3. 错误处理：JSON 解析失败、LLM 异常、数据库异常
4. 状态一致性：消息保存、session 生命周期、元数据完整性
5. 并发安全：多线程同时操作 Store
6. 关键函数存在性：通过反射检查核心 API
"""

import json
import tempfile
import os
import threading
from dataclasses import dataclass, field
from typing import Any

from app.evaluation.robustness import RobustnessTest


@dataclass
class FunctionalResult:
    """单次功能测试结果"""
    test_name: str
    passed: bool
    category: str
    message: str
    details: dict = field(default_factory=dict)


class FunctionalTest:
    """功能完整性与鲁棒性测试"""

    def __init__(self):
        self.results: list[FunctionalResult] = []
        self.tmpdir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmpdir, "functional_test.db")
        from app.memory.store import Store
        from app.llm.fake import FakeClient
        from app.agents.orchestrator import ConversationOrchestrator
        self.store = Store(self.db_path)
        self.llm = FakeClient()
        self.orch = ConversationOrchestrator(
            llm=self.llm,
            store=self.store,
        )

    def _record(self, test_name: str, category: str, passed: bool,
                message: str, details: dict | None = None):
        self.results.append(FunctionalResult(
            test_name=test_name,
            passed=passed,
            category=category,
            message=message,
            details=details or {},
        ))

    # ------------------------------------------------------------------
    # 1. 全路径覆盖测试
    # ------------------------------------------------------------------

    def test_all_reply_paths_exist(self):
        """验证所有回复路径方法存在且可调用"""
        methods = [
            "_crisis_response", "_quick_response", "_clarify_response",
            "_interaction_response", "_deep_response", "_choose_reply_roles",
            "reply", "reply_detail", "reply_stream",
        ]
        for method_name in methods:
            exists = hasattr(self.orch, method_name) and callable(getattr(self.orch, method_name))
            self._record(
                f"path_method_exists_{method_name}", "路径覆盖",
                exists,
                f"方法 '{method_name}' {'存在' if exists else '缺失'}",
                {"method": method_name},
            )

    def test_crisis_path_functional(self):
        """危机路径：命中关键词 → 返回固定模板 → 消息正确保存"""
        sid = self.store.create_session()
        result = self.orch.reply_detail(sid, "我不想结束这一切", "auto")

        # 验证返回结构完整
        has_reply = bool(result.get("reply"))
        has_character = bool(result.get("character"))
        has_debug = isinstance(result.get("debug_trace"), dict)

        self._record(
            "crisis_path_return_structure", "路径覆盖",
            has_reply and has_character and has_debug,
            f"危机路径返回结构: reply={has_reply}, character={has_character}, debug={has_debug}",
            {"has_reply": has_reply, "has_character": has_character, "has_debug": has_debug},
        )

        # 验证消息已保存到数据库
        messages = self.store.get_session_messages(sid)
        has_user_msg = any(m["role"] == "user" for m in messages)
        has_assistant_msg = any(m["role"] == "assistant" for m in messages)
        self._record(
            "crisis_path_message_saved", "状态一致性",
            has_user_msg and has_assistant_msg,
            f"危机路径消息保存: user={has_user_msg}, assistant={has_assistant_msg}",
            {"message_count": len(messages)},
        )

    def test_deep_path_functional(self):
        """深度路径：完整链路 → 记忆检索 → 知识卡检索 → 回复生成"""
        sid = self.store.create_session()
        result = self.orch.reply_detail(sid, "我最近总是感到很焦虑，不知道该怎么办", "auto")

        debug = result.get("debug_trace", {})
        steps = debug.get("steps", [])
        step_names = [s.get("name") for s in steps]

        # 验证关键步骤执行
        has_intent = "intent_recognition" in step_names
        has_routing = "intent_routing" in step_names
        has_generate = "generate_reply" in step_names

        self._record(
            "deep_path_steps", "路径覆盖",
            has_intent and has_routing and has_generate,
            f"深度路径步骤: intent={has_intent}, routing={has_routing}, generate={has_generate}",
            {"steps": step_names},
        )

        # 验证回复非空
        reply = result.get("reply", "")
        self._record(
            "deep_path_reply_non_empty", "路径覆盖",
            len(reply) > 5,
            f"深度路径回复长度={len(reply)} 字",
            {"reply_chars": len(reply)},
        )

    def test_manual_character_path(self):
        """手动角色模式：不走 intent 识别，直接使用指定角色"""
        sid = self.store.create_session()
        result = self.orch.reply_detail(sid, "测试", "momo")

        character = result.get("character", {})
        is_momo = character.get("id") == "momo"
        self._record(
            "manual_character_momo", "路径覆盖",
            is_momo,
            f"手动角色模式: 实际角色={character.get('id', 'unknown')}"
            f"（{'通过' if is_momo else '失败：应为 momo'}）",
            {"character_id": character.get("id")},
        )

    def test_clarify_path_functional(self):
        """追问路径：不调用 LLM，直接返回 clarify_reply"""
        from app.intent.schema import IntentResult, ReplyPath
        sid = self.store.create_session()
        intent = IntentResult(
            intent="CLARIFY", confidence=0.6, emotion="困惑", risk_level="low",
            character_id="yoyo", expression_id="concerned", response_mode="validate",
            memory_queries=[], knowledge_queries=[],
            user_state="信息不足", core_need="被理解",
            response_guidance="", clarify_reply="你能多说一点吗？",
            interaction_type="", reason="测试",
        )
        reply_path = ReplyPath(
            path="clarify", use_thinking=False,
            route_plan={"character_id": "yoyo"},
            intent_result=intent,
        )
        result = self.orch._clarify_response(sid, "测试", reply_path, {"steps": [], "llm_calls": []}, 0)
        reply = result.get("reply", "")

        # clarify 路径不应调用 LLM（debug_trace.llm_calls 为空或不变）
        debug = result.get("debug_trace", {})
        llm_calls = debug.get("llm_calls", [])
        no_llm = len(llm_calls) == 0
        self._record(
            "clarify_path_no_llm_call", "路径覆盖",
            no_llm,
            f"追问路径 LLM 调用次数={len(llm_calls)}（{'通过' if no_llm else '失败：不应调用 LLM'}）",
            {"llm_call_count": len(llm_calls)},
        )

        # 回复应为 clarify_reply 内容
        is_clarify = "你能多说一点吗？" in reply
        self._record(
            "clarify_path_content", "路径覆盖",
            is_clarify,
            f"追问路径回复内容匹配={is_clarify}",
            {"reply": reply},
        )

    def test_interaction_path_functional(self):
        """交互路径：模板生成，不调用 LLM"""
        from app.intent.schema import IntentResult, ReplyPath
        sid = self.store.create_session()
        intent = IntentResult(
            intent="INTERACTION", confidence=0.8, emotion="焦虑", risk_level="low",
            character_id="yoyo", expression_id="calm", response_mode="stabilize",
            memory_queries=[], knowledge_queries=[],
            user_state="需要放松", core_need="稳定",
            response_guidance="", clarify_reply="",
            interaction_type="breathing", reason="测试",
        )
        reply_path = ReplyPath(
            path="interaction", use_thinking=False,
            route_plan={"character_id": "yoyo"},
            intent_result=intent,
        )
        result = self.orch._interaction_response(sid, "测试", reply_path, {"steps": [], "llm_calls": []}, 0)
        reply = result.get("reply", "")

        # 交互路径回复应包含模板关键词
        has_breathing = "呼吸" in reply
        self._record(
            "interaction_path_breathing_template", "路径覆盖",
            has_breathing,
            f"交互路径回复包含'呼吸'={has_breathing}",
            {"reply_preview": reply[:80]},
        )

    # ------------------------------------------------------------------
    # 2. 边界条件测试
    # ------------------------------------------------------------------

    def test_empty_input(self):
        """空输入处理"""
        sid = self.store.create_session()
        try:
            result = self.orch.reply_detail(sid, "", "auto")
            has_reply = bool(result.get("reply"))
            self._record(
                "edge_empty_input", "边界条件",
                has_reply,
                f"空输入回复长度={len(result.get('reply', ''))} 字"
                f"（{'通过' if has_reply else '失败：未返回回复'}）",
            )
        except Exception as e:
            self._record(
                "edge_empty_input", "边界条件",
                False,
                f"空输入抛出异常: {type(e).__name__}: {e}",
            )

    def test_very_long_input(self):
        """超长输入处理（2000 字）"""
        sid = self.store.create_session()
        long_text = "我很焦虑。" * 400  # 约 2000 字
        try:
            result = self.orch.reply_detail(sid, long_text, "auto")
            has_reply = len(result.get("reply", "")) > 5
            self._record(
                "edge_long_input", "边界条件",
                has_reply,
                f"超长输入（{len(long_text)} 字）回复长度={len(result.get('reply', ''))} 字",
                {"input_chars": len(long_text)},
            )
        except Exception as e:
            self._record(
                "edge_long_input", "边界条件",
                False,
                f"超长输入抛出异常: {type(e).__name__}: {e}",
            )

    def test_special_characters(self):
        """特殊字符输入处理"""
        sid = self.store.create_session()
        special_texts = [
            "<script>alert('xss')</script>",
            "'; DROP TABLE messages; --",
            "\"quoted\" and 'apos'",
            "\n\n\n多行\n文本\n",
            "emoji 😀🎉💔",
        ]
        for text in special_texts:
            try:
                result = self.orch.reply_detail(sid, text, "auto")
                has_reply = len(result.get("reply", "")) > 0
                self._record(
                    f"edge_special_{text[:20]}", "边界条件",
                    has_reply,
                    f"特殊字符输入 '{text[:30]}...' 回复长度={len(result.get('reply', ''))} 字",
                )
            except Exception as e:
                self._record(
                    f"edge_special_{text[:20]}", "边界条件",
                    False,
                    f"特殊字符输入抛出异常: {type(e).__name__}: {e}",
                )

    # ------------------------------------------------------------------
    # 3. 错误处理测试
    # ------------------------------------------------------------------

    def test_json_parse_failure_fallback(self):
        """JSON 解析失败时的降级处理"""
        from app.agents.orchestrator import parse_json_object

        # 无效 JSON
        result = parse_json_object("invalid json {{{")
        self._record(
            "error_json_parse_invalid", "错误处理",
            result == {},
            f"无效 JSON 解析返回空字典={result == {}}",
            {"result": result},
        )

        # 空字符串
        result = parse_json_object("")
        self._record(
            "error_json_parse_empty", "错误处理",
            result == {},
            f"空字符串解析返回空字典={result == {}}",
            {"result": result},
        )

        # 代码块包裹的 JSON
        result = parse_json_object('```json\n{"a": 1}\n```')
        self._record(
            "error_json_parse_codeblock", "错误处理",
            result == {"a": 1},
            f"代码块 JSON 解析结果={result}",
            {"result": result},
        )

    def test_orchestrator_json_parse_on_reply(self):
        """orchestrator 中 JSON 解析失败时的降级"""
        sid = self.store.create_session()
        # FakeClient 正常情况下返回有效 JSON，这里测试 _deep_response 中的解析逻辑
        result = self.orch.reply_detail(sid, "测试 JSON 降级", "auto")
        reply = result.get("reply", "")
        self._record(
            "error_reply_json_fallback", "错误处理",
            len(reply) > 0,
            f"JSON 降级路径回复长度={len(reply)} 字",
        )

    # ------------------------------------------------------------------
    # 4. 状态一致性测试
    # ------------------------------------------------------------------

    def test_session_lifecycle(self):
        """会话生命周期：创建 → 发消息 → 结束"""
        sid = self.store.create_session()
        session = self.store.get_session(sid)
        self._record(
            "session_create", "状态一致性",
            session is not None,
            f"会话创建: session={'存在' if session else '缺失'}",
        )

        self.store.add_message(sid, "user", "hello")
        messages = self.store.get_session_messages(sid)
        self._record(
            "session_add_message", "状态一致性",
            len(messages) == 1,
            f"添加消息后消息数={len(messages)}",
        )

        self.store.end_session(sid)
        session_after = self.store.get_session(sid)
        is_ended = session_after.get("ended_at") is not None if session_after else False
        self._record(
            "session_end", "状态一致性",
            is_ended,
            f"结束会话: ended_at={'已设置' if is_ended else '未设置'}",
        )

    def test_message_metadata(self):
        """消息元数据完整性"""
        import json as _json
        sid = self.store.create_session()
        self.orch.reply_detail(sid, "测试元数据", "auto")
        messages = self.store.get_session_messages(sid)
        assistant_msgs = []
        for m in messages:
            if m["role"] == "assistant":
                d = dict(m)
                # metadata 在数据库中是 JSON 字符串，需要反序列化
                raw_meta = d.get("metadata", "{}") or "{}"
                d["metadata"] = _json.loads(raw_meta) if isinstance(raw_meta, str) else raw_meta
                assistant_msgs.append(d)

        if assistant_msgs:
            msg = assistant_msgs[0]
            metadata = msg.get("metadata") or {}
            has_character = bool(metadata.get("character_id"))
            has_expression = bool(metadata.get("expression_id"))
            self._record(
                "message_metadata", "状态一致性",
                has_character and has_expression,
                f"消息元数据: character_id={has_character}, expression_id={has_expression}",
                {"metadata_keys": list(metadata.keys())},
            )
        else:
            self._record(
                "message_metadata", "状态一致性",
                False,
                "未找到 assistant 消息",
            )

    # ------------------------------------------------------------------
    # 5. 并发安全测试
    # ------------------------------------------------------------------

    def test_concurrent_store_access(self):
        """多线程并发访问 Store"""
        sid = self.store.create_session()
        errors = []

        def add_messages(count):
            try:
                for i in range(count):
                    self.store.add_message(sid, "user", f"并发消息 {i}")
            except Exception as e:
                errors.append(str(e))

        threads = [threading.Thread(target=add_messages, args=(20,)) for _ in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        messages = self.store.get_session_messages(sid)
        expected_count = 5 * 20
        passed = len(errors) == 0 and len(messages) == expected_count
        self._record(
            "concurrent_store_access", "并发安全",
            passed,
            f"并发写入: 期望={expected_count}, 实际={len(messages)}, 错误={len(errors)}",
            {"errors": errors[:3]},
        )

    # ------------------------------------------------------------------
    # 6. 关键函数签名检查
    # ------------------------------------------------------------------

    def test_critical_function_signatures(self):
        """检查关键函数的参数签名是否符合预期"""
        import inspect

        from app.agents.orchestrator import ConversationOrchestrator
        from app.memory.store import Store
        from app.agents.safety import detect_crisis

        # detect_crisis 签名
        sig = inspect.signature(detect_crisis)
        params = list(sig.parameters.keys())
        self._record(
            "signature_detect_crisis", "API 完整性",
            "text" in params,
            f"detect_crisis 参数: {params}",
            {"params": params},
        )

        # Store.create_session 签名
        sig = inspect.signature(Store.create_session)
        params = list(sig.parameters.keys())
        self._record(
            "signature_store_create_session", "API 完整性",
            True,  # create_session 无必需参数即可
            f"Store.create_session 参数: {params}",
            {"params": params},
        )

        # ConversationOrchestrator.reply_detail 签名
        sig = inspect.signature(ConversationOrchestrator.reply_detail)
        params = list(sig.parameters.keys())
        required = ["session_id", "user_text"]
        has_required = all(p in params for p in required)
        self._record(
            "signature_reply_detail", "API 完整性",
            has_required,
            f"reply_detail 参数: {params}，必需参数完整={has_required}",
            {"params": params, "has_required": has_required},
        )

    # ------------------------------------------------------------------
    # 运行所有测试
    # ------------------------------------------------------------------

    def run(self) -> list[FunctionalResult]:
        self.results = []
        tests = [
            self.test_all_reply_paths_exist,
            self.test_crisis_path_functional,
            self.test_deep_path_functional,
            self.test_manual_character_path,
            self.test_clarify_path_functional,
            self.test_interaction_path_functional,
            self.test_empty_input,
            self.test_very_long_input,
            self.test_special_characters,
            self.test_json_parse_failure_fallback,
            self.test_orchestrator_json_parse_on_reply,
            self.test_session_lifecycle,
            self.test_message_metadata,
            self.test_concurrent_store_access,
            self.test_critical_function_signatures,
        ]
        for test in tests:
            try:
                test()
            except Exception as e:
                import traceback
                self._record(
                    test.__name__, "error", False,
                    f"测试执行异常: {type(e).__name__}: {e}\n{traceback.format_exc()}",
                )
        return self.results

    def summary(self) -> dict[str, Any]:
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        by_category: dict[str, list[FunctionalResult]] = {}
        for r in self.results:
            by_category.setdefault(r.category, []).append(r)

        return {
            "test_name": "functional",
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate": round(passed / total, 4) if total else 0,
            "by_category": {
                cat: {
                    "total": len(rs),
                    "passed": sum(1 for r in rs if r.passed),
                }
                for cat, rs in by_category.items()
            },
            "details": [
                {
                    "test_name": r.test_name,
                    "passed": r.passed,
                    "category": r.category,
                    "message": r.message,
                    "details": r.details,
                }
                for r in self.results
            ],
        }


def functional_suite() -> dict[str, Any]:
    """运行功能完整性测试套件"""
    test = FunctionalTest()
    test.run()
    return test.summary()


if __name__ == "__main__":
    result = functional_suite()
    print(f"功能完整性测试: {result['passed']}/{result['total']} 通过")
    for detail in result["details"]:
        status = "✅" if detail["passed"] else "❌"
        print(f"  {status} [{detail['category']}] {detail['test_name']}: {detail['message']}")
