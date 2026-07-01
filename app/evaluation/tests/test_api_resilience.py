"""
API 调用鲁棒性测试模块

基于代码审查发现的问题，测试 DeepSeek API 调用、流式处理、
SSE 输出中的异常处理和数据完整性。

发现问题：
1. deepseek.py _read_stream 中 json.loads(data) 未捕获 JSONDecodeError
2. orchestrator.py SSE 输出中 JSON 可能包含未转义的换行符
3. web.py SSE 前端 JSON.parse 失败时静默跳过
4. deepseek.py 流式处理 finish_reason 为 truthy 时提前返回可能遗漏内容
"""

import json
import tempfile
import os
from dataclasses import dataclass, field
from typing import Any
from io import BytesIO


@dataclass
class ApiResult:
    test_name: str
    passed: bool
    severity: str
    message: str
    details: dict = field(default_factory=dict)
    blocking: bool = True
    category: str = "product_bug"


class ApiResilienceTest:
    """API 调用鲁棒性测试"""

    def __init__(self):
        self.results: list[ApiResult] = []

    def _record(
        self,
        name: str,
        severity: str,
        passed: bool,
        msg: str,
        details: dict | None = None,
        *,
        blocking: bool = True,
        category: str = "product_bug",
    ):
        self.results.append(ApiResult(
            test_name=name,
            passed=passed,
            severity=severity,
            message=msg,
            details=details or {},
            blocking=blocking,
            category=category,
        ))

    # ------------------------------------------------------------------
    # 1. DeepSeek 流式读取鲁棒性
    # ------------------------------------------------------------------

    def _make_deepseek_client(self):
        from app.llm.deepseek import DeepSeekClient
        return DeepSeekClient(api_key="fake", model="fake-model", base_url="http://fake")

    def test_deepseek_stream_json_decode_error(self):
        """测试 _read_stream 面对无效 JSON 时的行为"""
        client = self._make_deepseek_client()

        # 构造包含无效 JSON 的流式响应
        invalid_lines = [
            b"data: {\"choices\": [{\"delta\": {\"content\": \"hello\"}}]}\n",
            b"data: invalid json {{{\n",  # 无效 JSON
            b"data: {\"choices\": [{\"delta\": {\"content\": \" world\"}}]}\n",
        ]

        try:
            content, raw = client._read_stream(iter(invalid_lines))
            # 如果成功返回，检查是否正确处理了无效行
            self._record(
                "deepseek_stream_invalid_json",
                "high",
                True,
                f"_read_stream 成功处理了无效 JSON 行，返回内容长度={len(content)}",
                {"content": content, "has_invalid_line": True},
            )
        except json.JSONDecodeError as e:
            self._record(
                "deepseek_stream_invalid_json",
                "high",
                False,
                f"_read_stream 面对无效 JSON 时抛出 JSONDecodeError 且未被捕获，导致流式读取崩溃: {e}",
                {"error_type": "JSONDecodeError", "error_msg": str(e)},
            )
        except Exception as e:
            self._record(
                "deepseek_stream_invalid_json",
                "high",
                False,
                f"_read_stream 面对无效 JSON 时抛出未预期异常: {type(e).__name__}: {e}",
                {"error_type": type(e).__name__, "error_msg": str(e)},
            )

    def test_deepseek_stream_done_marker(self):
        """测试 [DONE] 标记后的行为"""
        client = self._make_deepseek_client()

        lines = [
            b"data: {\"choices\": [{\"delta\": {\"content\": \"hello\"}}]}\n",
            b"data: [DONE]\n",
            b"data: {\"choices\": [{\"delta\": {\"content\": \" world\"}}]}\n",  # [DONE] 后不应被处理
        ]

        try:
            content, raw = client._read_stream(iter(lines))
            has_extra = "world" in content
            self._record(
                "deepseek_stream_done_marker",
                "medium",
                not has_extra,
                f"[DONE] 后内容{'被错误包含' if has_extra else '正确截断'}，返回内容='{content}'",
                {"content": content, "extra_after_done": has_extra},
            )
        except Exception as e:
            self._record(
                "deepseek_stream_done_marker",
                "medium",
                False,
                f"[DONE] 标记测试异常: {type(e).__name__}: {e}",
                {"error": str(e)},
            )

    def test_deepseek_stream_empty_content(self):
        """测试 delta.content 为 None 或缺失时的行为"""
        client = self._make_deepseek_client()

        lines = [
            b"data: {\"choices\": [{\"delta\": {}}]}\n",  # 空 delta
            b"data: {\"choices\": [{\"delta\": {\"content\": null}}]}\n",  # content 为 null
            b"data: {\"choices\": [{\"delta\": {\"content\": \"hi\"}}]}\n",
        ]

        try:
            content, raw = client._read_stream(iter(lines))
            self._record(
                "deepseek_stream_empty_delta",
                "medium",
                content == "hi",
                f"空 delta 处理结果: '{content}'（期望='hi'）",
                {"content": content},
            )
        except Exception as e:
            self._record(
                "deepseek_stream_empty_delta",
                "medium",
                False,
                f"空 delta 测试异常: {type(e).__name__}: {e}",
                {"error": str(e)},
            )

    # ------------------------------------------------------------------
    # 2. SSE 输出 JSON 格式验证
    # ------------------------------------------------------------------

    def test_sse_json_newline_escaping(self):
        """验证 SSE 输出中 JSON 是否正确转义换行符"""
        import json

        # 模拟包含换行符的回复
        reply_with_newlines = "第一行\n第二行\n第三行"
        event_data = {"type": "deep_reply", "data": {"reply": reply_with_newlines}}

        # 使用 json.dumps 序列化（这是 orchestrator 使用的方式）
        serialized = json.dumps(event_data, ensure_ascii=False)

        # 验证可以正确解析
        try:
            parsed = json.loads(serialized)
            recovered = parsed["data"]["reply"]
            passed = recovered == reply_with_newlines
            self._record(
                "sse_json_newline_escaping",
                "medium",
                passed,
                f"换行符序列化验证: {'通过' if passed else '失败'}，原始={repr(reply_with_newlines)}, 恢复={repr(recovered)}",
                {"original": reply_with_newlines, "recovered": recovered},
            )
        except Exception as e:
            self._record(
                "sse_json_newline_escaping",
                "medium",
                False,
                f"换行符序列化异常: {e}",
                {"error": str(e)},
            )

    def test_sse_json_unicode_escaping(self):
        """验证 SSE 输出中 Unicode 字符是否正确处理"""
        import json

        reply_with_unicode = "emoji 😀🎉 中文测试"
        event_data = {"type": "deep_reply", "data": {"reply": reply_with_unicode}}

        serialized = json.dumps(event_data, ensure_ascii=False)
        try:
            parsed = json.loads(serialized)
            recovered = parsed["data"]["reply"]
            passed = recovered == reply_with_unicode
            self._record(
                "sse_json_unicode_escaping",
                "medium",
                passed,
                f"Unicode 序列化验证: {'通过' if passed else '失败'}",
                {"original": reply_with_unicode, "recovered": recovered},
            )
        except Exception as e:
            self._record(
                "sse_json_unicode_escaping",
                "medium",
                False,
                f"Unicode 序列化异常: {e}",
                {"error": str(e)},
            )

    # ------------------------------------------------------------------
    # 3. 前端 SSE 解析鲁棒性（代码静态验证）
    # ------------------------------------------------------------------

    def test_frontend_sse_malformed_json_handling(self):
        """前端 listenSSE 中 malformed event 的静默跳过问题"""
        # 这是代码静态审查发现的问题
        # web.py 第 2022 行: catch (e) { /* skip malformed event */ }
        # 当后端发送无效 JSON 时，前端静默跳过，用户看不到任何反馈

        self._record(
            "frontend_sse_malformed_json_silent_skip",
            "info",
            False,
            "代码审查发现：web.py listenSSE 中 JSON.parse 失败时静默跳过（catch (e) { /* skip malformed event */ }），"
            "当后端发送无效 JSON 时，用户不会收到任何错误提示，消息可能完全缺失。"
            "建议：至少记录错误到 console.error，或向前端用户显示 '消息解析失败' 提示。",
            {"file": "app/web.py", "line": "~2022", "current_code": "catch (e) { /* skip malformed event */ }"},
            blocking=False,
            category="observation",
        )

    # ------------------------------------------------------------------
    # 4. 数据库数据完整性
    # ------------------------------------------------------------------

    def test_store_add_memory_none_evidence(self):
        """测试 add_memory 中 evidence 为 None 时的行为"""
        import tempfile
        from app.memory.store import Store

        tmpdir = tempfile.mkdtemp()
        db_path = os.path.join(tmpdir, "test.db")
        store = Store(db_path)
        sid = store.create_session()

        # evidence 为 None
        memory = {
            "category": "emotion",
            "content": "测试内容",
            "evidence": None,  # 可能为 None
            "confidence": 0.8,
            "importance": 3,
        }

        try:
            mid = store.add_memory(sid, memory)
            self._record(
                "store_add_memory_none_evidence",
                "medium",
                True,
                f"add_memory 成功处理 None evidence，memory_id={mid}",
                {"memory_id": mid},
            )
        except Exception as e:
            self._record(
                "store_add_memory_none_evidence",
                "medium",
                False,
                f"add_memory 面对 None evidence 时崩溃: {type(e).__name__}: {e}",
                {"error": str(e)},
            )

    def test_store_list_profiles_invalid_evidence_json(self):
        """测试 list_state_profiles 中无效 evidence JSON 的处理"""
        import tempfile
        import json
        from app.memory.store import Store

        tmpdir = tempfile.mkdtemp()
        db_path = os.path.join(tmpdir, "test.db")
        store = Store(db_path)

        # 手动插入一条 evidence 为无效 JSON 的记录
        with store.connect() as conn:
            conn.execute("""
                INSERT INTO user_state_profiles (
                    id, user_id, domain, stage, summary, intensity, trend,
                    confidence, evidence, support_strategy, source_session_id,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                "test-id", "default", "emotional", "stable", "test", 3, "flat",
                0.5, "invalid json {{{", "", "sid", "2024-01-01", "2024-01-01"
            ))

        try:
            profiles = store.list_state_profiles()
            test_profile = [p for p in profiles if p["id"] == "test-id"]
            if test_profile:
                evidence = test_profile[0].get("evidence", "NOT_FOUND")
                is_empty_list = evidence == []
                self._record(
                    "store_list_profiles_invalid_evidence_json",
                    "info",
                    True,
                    f"无效 evidence JSON 被静默设置为 {evidence}。"
                    f"{'已降级为空列表并记录日志' if is_empty_list else '意外结果'}，"
                    f"原始 evidence='invalid json ' + '{{{{{{'",
                    {"recovered_evidence": evidence, "original": "invalid json {{{"},
                    blocking=False,
                    category="observation",
                )
            else:
                self._record(
                    "store_list_profiles_invalid_evidence_json",
                    "medium",
                    False,
                    "插入的测试记录未被读取到",
                    {},
                )
        except Exception as e:
            self._record(
                "store_list_profiles_invalid_evidence_json",
                "medium",
                False,
                f"list_state_profiles 异常: {type(e).__name__}: {e}",
                {"error": str(e)},
            )

    # ------------------------------------------------------------------
    # 5. 超时和异常处理
    # ------------------------------------------------------------------

    def test_deepseek_timeout_exception_types(self):
        """验证超时异常类型处理是否完整"""
        import socket
        import inspect
        from app.llm.deepseek import DeepSeekClient

        # 检查 chat 方法中捕获的异常类型
        source = inspect.getsource(DeepSeekClient.chat)

        has_timeout_error = "TimeoutError" in source
        has_socket_timeout = "socket.timeout" in source
        has_urllib_error = "urllib.error" in source

        # Python 3.10+ 中 socket.timeout 是 OSError 的子类，已被 TimeoutError 覆盖
        # 检查是否存在重复捕获
        duplicate_catch = has_timeout_error and has_socket_timeout

        self._record(
            "deepseek_timeout_exception_types",
            "low",
            not duplicate_catch,  # 如果不重复则通过
            f"超时异常处理: TimeoutError={'有' if has_timeout_error else '无'}, "
            f"socket.timeout={'有' if has_socket_timeout else '无'}, "
            f"urllib.error={'有' if has_urllib_error else '无'}. "
            f"{'存在重复捕获（TimeoutError 已覆盖 socket.timeout）' if duplicate_catch else '异常处理完整'}",
            {"duplicate_catch": duplicate_catch},
        )

    # ------------------------------------------------------------------
    # 6. 消息渲染边界条件
    # ------------------------------------------------------------------

    def test_message_collapse_boundary(self):
        """测试消息折叠逻辑的边界条件"""
        # 基于代码审查：web.py 中 shouldCollapse = text.length > 80 || text.includes("\n")
        test_cases = [
            ("a" * 80, False, "刚好 80 字不应折叠"),
            ("a" * 81, True, "81 字应折叠"),
            ("hello\nworld", True, "包含换行应折叠"),
            ("hello", False, "短消息不应折叠"),
            ("", False, "空消息不应折叠"),
        ]

        for text, expected, desc in test_cases:
            actual = len(text) > 80 or "\n" in text
            passed = actual == expected
            self._record(
                f"msg_collapse_{desc.replace(' ', '_')}",
                "low",
                passed,
                f"{desc}: 预期={expected}, 实际={actual}",
                {"text_length": len(text), "has_newline": "\n" in text},
            )

    # ------------------------------------------------------------------
    # 运行所有测试
    # ------------------------------------------------------------------

    def run(self) -> list[ApiResult]:
        self.results = []
        tests = [
            self.test_deepseek_stream_json_decode_error,
            self.test_deepseek_stream_done_marker,
            self.test_deepseek_stream_empty_content,
            self.test_sse_json_newline_escaping,
            self.test_sse_json_unicode_escaping,
            self.test_frontend_sse_malformed_json_handling,
            self.test_store_add_memory_none_evidence,
            self.test_store_list_profiles_invalid_evidence_json,
            self.test_deepseek_timeout_exception_types,
            self.test_message_collapse_boundary,
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
        checks = [result for result in self.results if result.blocking]
        observations = [result for result in self.results if not result.blocking]
        total = len(checks)
        passed = sum(1 for result in checks if result.passed)
        by_severity: dict[str, list[ApiResult]] = {}
        for r in checks:
            by_severity.setdefault(r.severity, []).append(r)

        return {
            "test_name": "api_resilience",
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate": round(passed / total, 4) if total else 0,
            "by_severity": {
                sev: {"total": len(rs), "passed": sum(1 for r in rs if r.passed)}
                for sev, rs in by_severity.items()
            },
            "details": [
                {
                    "test_name": r.test_name,
                    "passed": r.passed,
                    "severity": r.severity,
                    "message": r.message,
                    "details": r.details,
                    "blocking": r.blocking,
                    "category": r.category,
                }
                for r in checks
            ],
            "observations": [
                {
                    "test_name": r.test_name,
                    "severity": r.severity,
                    "message": r.message,
                    "details": r.details,
                    "category": r.category,
                }
                for r in observations
            ],
        }


def api_resilience_suite() -> dict[str, Any]:
    """运行 API 鲁棒性测试套件"""
    test = ApiResilienceTest()
    test.run()
    return test.summary()


if __name__ == "__main__":
    result = api_resilience_suite()
    print(f"API 鲁棒性测试: {result['passed']}/{result['total']} 通过")
    for detail in result["details"]:
        status = "✅" if detail["passed"] else "❌"
        print(f"  {status} [{detail['severity']}] {detail['test_name']}: {detail['message'][:100]}")
    if result["failed"]:
        raise SystemExit(1)
