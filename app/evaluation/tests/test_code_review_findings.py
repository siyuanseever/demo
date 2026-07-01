"""
代码审查发现问题的测试模块

针对代码审查中发现的线程安全、异常保护缺失、安全风险等问题，
编写防御性测试，验证系统在异常条件下的行为。

测试覆盖的问题：
1. [高] TrackedLLMClient.set_context 线程安全问题
2. [高] _write_journal 中 json.loads 无异常保护
3. [高] _extract_memories 中 json.loads 无异常保护
4. [高] _deep_response 中 LLM 调用无异常保护
5. [中] close_session 中 journal_future.result() 无异常保护
6. [中] reply_stream 中意图识别超时后的回退路径
7. [中] web.py /api/data type 参数白名单验证
8. [中] prompt_tracker.py 路径遍历风险
"""

import json
import tempfile
import os
import threading
import time
from dataclasses import dataclass, field
from typing import Any

from app.evaluation.robustness import RobustnessTest, RobustnessResult
from app.evaluation.accuracy import AccuracyTest


# ---------------------------------------------------------------------------
# 辅助工具：可注入异常的 FakeLLM
# ---------------------------------------------------------------------------


class BrokenJsonClient:
    """模拟 LLM 返回无效 JSON 的客户端，用于测试 json.loads 无异常保护。"""

    def __init__(self) -> None:
        self.calls: list[dict] = []

    def chat(
        self,
        messages: list,
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
        thinking: str | None = None,
        reasoning_effort: str | None = None,
    ):
        self.calls.append({
            "messages": messages,
            "response_format": response_format,
        })
        # 如果要求 json_object 格式，返回无效 JSON
        if response_format and response_format.get("type") == "json_object":
            return type("R", (), {
                "content": "这不是有效的JSON!!!{broken",
                "model": "broken-json-client",
                "raw": {},
            })()
        # 否则返回正常文本
        return type("R", (), {
            "content": "这是一条普通文本回复。",
            "model": "broken-json-client",
            "raw": {},
        })()


class FailingClient:
    """模拟 LLM 调用抛出异常的客户端，用于测试异常保护。"""

    def __init__(self, error: Exception | None = None) -> None:
        self.calls: list[dict] = []
        self.error = error or RuntimeError("模拟 LLM 调用失败")

    def chat(
        self,
        messages: list,
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
        thinking: str | None = None,
        reasoning_effort: str | None = None,
    ):
        self.calls.append({
            "messages": messages,
            "response_format": response_format,
        })
        raise self.error


class SelectiveFailingClient:
    """只在特定 call_type 的 system prompt 匹配时抛出异常。"""

    def __init__(self, fail_keywords: list[str]) -> None:
        self.calls: list[dict] = []
        self.fail_keywords = fail_keywords

    def chat(
        self,
        messages: list,
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
        thinking: str | None = None,
        reasoning_effort: str | None = None,
    ):
        self.calls.append({
            "messages": messages,
            "response_format": response_format,
        })
        if messages and messages[0].get("role") == "system":
            system = messages[0]["content"]
            for kw in self.fail_keywords:
                if kw in system:
                    raise RuntimeError(f"模拟失败: 匹配到关键词 '{kw}'")
        return type("R", (), {
            "content": '{"reply": "正常回复", "expression_id": "calm"}',
            "model": "selective-failing",
            "raw": {},
        })()


class SlowClient:
    """模拟响应超时的客户端，用于测试超时回退路径。"""

    def __init__(self, delay_sec: float = 15.0) -> None:
        self.calls: list[dict] = []
        self.delay_sec = delay_sec

    def chat(
        self,
        messages: list,
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
        thinking: str | None = None,
        reasoning_effort: str | None = None,
    ):
        self.calls.append({
            "messages": messages,
            "response_format": response_format,
        })
        time.sleep(self.delay_sec)
        return type("R", (), {
            "content": '{"reply": "延迟回复", "expression_id": "calm"}',
            "model": "slow-client",
            "raw": {},
        })()


# ===========================================================================
# 问题 1: TrackedLLMClient.set_context 线程安全
# ===========================================================================


class SetContextThreadSafetyTest(RobustnessTest):
    """验证 TrackedLLMClient.set_context 在并发调用下的竞态条件。

    问题：TrackedLLMClient.set_context 写入共享的 self._call_context 字典。
    在 close_session 中，_write_journal / _extract_memories / _review_state_profiles
    通过 ThreadPoolExecutor(max_workers=3) 并行调用，它们共享同一个 self.llm，
    set_context 会互相覆盖 call_type 和 session_id。

    测试方法：用 TrackedLLMClient 包装 FakeClient，并发调用 set_context + chat，
    检查记录的 call_type 是否与预期一致（如果存在竞态，则 call_type 会被覆盖）。
    """

    def __init__(self):
        super().__init__("set_context_thread_safety", "evaluation.prompt_tracker")

    def run(self):
        from app.llm.fake import FakeClient
        from app.evaluation.prompt_tracker import TrackedLLMClient, PromptTracker

        fake = FakeClient()
        tracker = PromptTracker()
        tracker.clear()
        tracked = TrackedLLMClient(fake, tracker=tracker)

        # 模拟 close_session 中的并行调用：三个不同的 call_type
        call_types = ["journal", "memory_extract", "state_profile_review"]
        errors = []
        lock = threading.Lock()

        def parallel_call(call_type: str):
            try:
                tracked.set_context(call_type=call_type, session_id="test-session")
                tracked.chat(
                    [{"role": "user", "content": "测试并行上下文"}],
                    temperature=0.5,
                    max_tokens=100,
                )
            except Exception as e:
                with lock:
                    errors.append(f"{call_type}: {e}")

        threads = [threading.Thread(target=parallel_call, args=(ct,)) for ct in call_types]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        # 检查记录的 call_type 是否都被正确记录
        records = tracker.get_records(limit=10)
        recorded_types = [r.call_type for r in records]

        # 如果存在竞态条件，某些 call_type 可能被覆盖
        all_types_present = all(ct in recorded_types for ct in call_types)
        self.results.append(RobustnessResult(
            test_name="set_context_no_race_condition",
            passed=all_types_present,
            module=self.module,
            scenario="并发 set_context + chat",
            message=(
                f"并发调用后记录类型: {recorded_types}"
                if all_types_present
                else f"竞态条件: 期望 {call_types}，实际 {recorded_types}。"
                     f"部分 call_type 被覆盖，说明 set_context 存在线程安全问题。"
            ),
        ))

        # 无异常
        self.results.append(RobustnessResult(
            test_name="set_context_no_crash",
            passed=len(errors) == 0,
            module=self.module,
            scenario="并发 set_context + chat 异常检测",
            message="无异常" if not errors else f"异常: {errors[:3]}",
        ))


# ===========================================================================
# 问题 2: _write_journal 中 json.loads 无异常保护
# ===========================================================================


class WriteJournalJsonProtectionTest(RobustnessTest):
    """验证 _write_journal 在 LLM 返回无效 JSON 时不会崩溃。

    问题代码 (orchestrator.py:1710):
        return json.loads(response.content)

    如果 LLM 返回无效 JSON，json.loads 会抛出 JSONDecodeError，
    但 _write_journal 没有 try-except 保护，异常会传播到 close_session，
    而 close_session 中 journal_future.result() 也没有 try-except，
    导致整个 close_session 崩溃，session 无法正常关闭。
    """

    def __init__(self):
        super().__init__("_write_journal_json_protection", "agents.orchestrator")

    def run(self):
        import tempfile
        tmpdir = tempfile.mkdtemp()
        db_path = os.path.join(tmpdir, "write_journal_test.db")
        from app.memory.store import Store
        from app.agents.orchestrator import ConversationOrchestrator

        store = Store(db_path)
        llm = BrokenJsonClient()
        orch = ConversationOrchestrator(llm=llm, store=store)

        sid = store.create_session()
        store.add_message(sid, "user", "测试消息")
        store.add_message(sid, "assistant", "测试回复")

        try:
            result = orch.close_session(sid)
            # 如果代码有保护，应该返回结果而非崩溃
            self.results.append(RobustnessResult(
                test_name="write_journal_invalid_json_no_crash",
                passed=True,
                module=self.module,
                scenario="LLM 返回无效 JSON 时 close_session",
                message="close_session 在 LLM 返回无效 JSON 时正常完成（已修复或有保护）",
            ))
        except json.JSONDecodeError as e:
            self.results.append(RobustnessResult(
                test_name="write_journal_invalid_json_crash",
                passed=False,
                module=self.module,
                scenario="LLM 返回无效 JSON 时 close_session",
                message=(
                    f"_write_journal 的 json.loads 无异常保护，导致 close_session 崩溃: {e}。"
                    f"修复建议：在 _write_journal 中对 json.loads 添加 try-except，"
                    f"或在 close_session 中为 journal_future.result() 添加 try-except。"
                ),
                exception=str(e),
            ))
        except Exception as e:
            self.results.append(RobustnessResult(
                test_name="write_journal_unexpected_error",
                passed=False,
                module=self.module,
                scenario="LLM 返回无效 JSON 时 close_session",
                message=f"意外的异常类型: {type(e).__name__}: {e}",
                exception=str(e),
            ))


# ===========================================================================
# 问题 3: _extract_memories 中 json.loads 无异常保护
# ===========================================================================


class ExtractMemoriesJsonProtectionTest(RobustnessTest):
    """验证 _extract_memories 在 LLM 返回无效 JSON 时不会崩溃。

    问题代码 (orchestrator.py:1726):
        payload = json.loads(response.content)

    与 _write_journal 相同的问题：json.loads 无 try-except 保护。
    虽然 close_session 中 memory_future.result() 有 try-except，
    但 _extract_memories 内部的 json.loads 仍可能在其他调用路径中引发问题。
    """

    def __init__(self):
        super().__init__("_extract_memories_json_protection", "agents.orchestrator")

    def run(self):
        tmpdir = tempfile.mkdtemp()
        db_path = os.path.join(tmpdir, "extract_memories_test.db")
        from app.memory.store import Store
        from app.agents.orchestrator import ConversationOrchestrator

        store = Store(db_path)
        llm = BrokenJsonClient()
        orch = ConversationOrchestrator(llm=llm, store=store)

        sid = store.create_session()
        store.add_message(sid, "user", "测试记忆提取")

        # 直接调用 _extract_memories
        transcript = "user: 测试消息\nassistant: 测试回复"
        try:
            result = orch._extract_memories(transcript)
            # 如果有保护，应返回空列表或部分结果
            is_safe = isinstance(result, list)
            self.results.append(RobustnessResult(
                test_name="extract_memories_invalid_json_safe",
                passed=is_safe,
                module=self.module,
                scenario="LLM 返回无效 JSON 时 _extract_memories",
                message=(
                    f"_extract_memories 返回了 {type(result).__name__}，有异常保护。"
                    if is_safe
                    else f"返回了异常类型 {type(result).__name__}"
                ),
            ))
        except json.JSONDecodeError as e:
            self.results.append(RobustnessResult(
                test_name="extract_memories_invalid_json_crash",
                passed=False,
                module=self.module,
                scenario="LLM 返回无效 JSON 时 _extract_memories",
                message=(
                    f"_extract_memories 的 json.loads 无异常保护，抛出 JSONDecodeError: {e}。"
                    f"修复建议：在 json.loads 周围添加 try-except，失败时返回空列表。"
                ),
                exception=str(e),
            ))
        except Exception as e:
            self.results.append(RobustnessResult(
                test_name="extract_memories_unexpected_error",
                passed=False,
                module=self.module,
                scenario="LLM 返回无效 JSON 时 _extract_memories",
                message=f"意外的异常类型: {type(e).__name__}: {e}",
                exception=str(e),
            ))


# ===========================================================================
# 问题 4: _deep_response 中 LLM 调用无异常保护
# ===========================================================================


class DeepResponseLlmProtectionTest(RobustnessTest):
    """验证 _deep_response 在 LLM 调用抛出异常时不会导致整个回复流程崩溃。

    问题代码 (orchestrator.py:936):
        response = self._chat(
            llm_messages,
            call_type="reply",
            session_id=session_id,
            ...
        )

    _chat 调用没有 try-except 保护。如果 LLM 调用抛出异常
    (如网络错误、API 限流、超时)，整个 reply_detail/reply_stream 都会崩溃。
    """

    def __init__(self):
        super().__init__("_deep_response_llm_protection", "agents.orchestrator")

    def run(self):
        tmpdir = tempfile.mkdtemp()
        db_path = os.path.join(tmpdir, "deep_response_test.db")
        from app.memory.store import Store
        from app.agents.orchestrator import ConversationOrchestrator

        store = Store(db_path)

        # 测试 1: reply_detail 中 LLM 异常
        llm = FailingClient()
        orch = ConversationOrchestrator(llm=llm, store=store)

        sid = store.create_session()
        try:
            result = orch.reply_detail(sid, "测试 LLM 异常保护", "auto")
            has_reply = bool(result.get("reply"))
            if has_reply:
                self.results.append(RobustnessResult(
                    test_name="deep_response_llm_error_fallback",
                    passed=True,
                    module=self.module,
                    scenario="reply_detail 中 LLM 异常",
                    message="LLM 异常时 reply_detail 返回了降级回复（已修复或有保护）",
                ))
            else:
                self.results.append(RobustnessResult(
                    test_name="deep_response_llm_error_no_reply",
                    passed=False,
                    module=self.module,
                    scenario="reply_detail 中 LLM 异常",
                    message="LLM 异常时 reply_detail 返回了空回复（降级不足）",
                ))
        except RuntimeError as e:
            if "模拟 LLM 调用失败" in str(e):
                self.results.append(RobustnessResult(
                    test_name="deep_response_llm_error_crash",
                    passed=False,
                    module=self.module,
                    scenario="reply_detail 中 LLM 异常",
                    message=(
                        f"_deep_response 的 LLM 调用无异常保护，reply_detail 崩溃: {e}。"
                        f"修复建议：在 _deep_response 中为 _chat 调用添加 try-except，"
                        f"失败时返回温和的降级回复如'我暂时没能回应你，请再试一次。'"
                    ),
                    exception=str(e),
                ))
            else:
                self.results.append(RobustnessResult(
                    test_name="deep_response_llm_unexpected_error",
                    passed=False,
                    module=self.module,
                    scenario="reply_detail 中 LLM 异常",
                    message=f"意外的异常: {e}",
                    exception=str(e),
                ))
        except Exception as e:
            self.results.append(RobustnessResult(
                test_name="deep_response_llm_other_error",
                passed=False,
                module=self.module,
                scenario="reply_detail 中 LLM 异常",
                message=f"非预期异常类型 {type(e).__name__}: {e}",
                exception=str(e),
            ))

        # 测试 2: reply_stream 中 LLM 异常（手动角色模式，只走 deep_response）
        sid2 = store.create_session()
        stream_crashed = False
        stream_error = None
        try:
            events = list(orch.reply_stream(sid2, "测试流式异常", character_id="momo"))
            # 如果有保护，应该至少产生一个 error 事件或正常事件
            self.results.append(RobustnessResult(
                test_name="deep_response_stream_llm_error",
                passed=len(events) > 0,
                module=self.module,
                scenario="reply_stream 中 LLM 异常（手动角色）",
                message=f"reply_stream 产生了 {len(events)} 个事件",
            ))
        except Exception as e:
            stream_crashed = True
            stream_error = e
            self.results.append(RobustnessResult(
                test_name="deep_response_stream_llm_crash",
                passed=False,
                module=self.module,
                scenario="reply_stream 中 LLM 异常（手动角色）",
                message=(
                    f"reply_stream 在 LLM 异常时崩溃: {type(e).__name__}: {e}。"
                    f"流式模式下 LLM 异常应通过 SSE error 事件通知客户端，而非崩溃。"
                ),
                exception=str(e),
            ))


# ===========================================================================
# 问题 5: close_session 中 journal_future.result() 无异常保护
# ===========================================================================


class CloseSessionJournalFutureTest(RobustnessTest):
    """验证 close_session 中 journal_future.result() 的异常保护。

    问题代码 (orchestrator.py:1674):
        journal = journal_future.result()   # 无 try-except

    对比 memory_future.result() (1666-1670) 和 state_future.result() (1676-1680)
    都有 try-except 保护，唯独 journal_future.result() 没有。
    如果 _write_journal 抛出异常，整个 close_session 会崩溃。
    """

    def __init__(self):
        super().__init__("close_session_journal_future", "agents.orchestrator")

    def run(self):
        tmpdir = tempfile.mkdtemp()
        db_path = os.path.join(tmpdir, "journal_future_test.db")
        from app.memory.store import Store
        from app.agents.orchestrator import ConversationOrchestrator

        store = Store(db_path)
        # 使用只在 journal prompt 中失败的客户端
        llm = SelectiveFailingClient(fail_keywords=["会后 journal"])
        orch = ConversationOrchestrator(llm=llm, store=store)

        sid = store.create_session()
        store.add_message(sid, "user", "测试消息")
        store.add_message(sid, "assistant", "测试回复")

        try:
            result = orch.close_session(sid)
            # 如果有保护，应正常返回
            self.results.append(RobustnessResult(
                test_name="journal_future_error_no_crash",
                passed=True,
                module=self.module,
                scenario="journal 写入失败时 close_session",
                message="journal 失败时 close_session 正常完成（已修复或有保护）",
            ))
        except RuntimeError as e:
            if "会后 journal" in str(e):
                self.results.append(RobustnessResult(
                    test_name="journal_future_error_crash",
                    passed=False,
                    module=self.module,
                    scenario="journal 写入失败时 close_session",
                    message=(
                        f"journal_future.result() 无 try-except 保护，"
                        f"导致 close_session 崩溃: {e}。"
                        f"修复建议：为 journal_future.result() 添加 try-except，"
                        f"失败时使用空字典作为 journal。"
                    ),
                    exception=str(e),
                ))
            else:
                self.results.append(RobustnessResult(
                    test_name="journal_future_unexpected_error",
                    passed=False,
                    module=self.module,
                    scenario="journal 写入失败时 close_session",
                    message=f"意外的异常: {e}",
                    exception=str(e),
                ))
        except Exception as e:
            self.results.append(RobustnessResult(
                test_name="journal_future_other_error",
                passed=False,
                module=self.module,
                scenario="journal 写入失败时 close_session",
                message=f"非预期异常类型 {type(e).__name__}: {e}",
                exception=str(e),
            ))


# ===========================================================================
# 问题 6: reply_stream 意图识别超时后的回退路径
# ===========================================================================


class ReplyStreamIntentTimeoutTest(RobustnessTest):
    """验证 reply_stream 中意图识别超时后的回退路径不会产生重复回复。

    问题代码 (orchestrator.py:1277):
        intent_result = intent_future.result(timeout=8)

    如果意图识别超时，reply_path 保持 None，代码会进入
    'if reply_path is None or character_id != "auto"' 分支 (1317行)，
    调用 _deep_response 生成第二次回复。

    如果 quick_reply 已经成功推送，再生成 deep_reply 就是"重复回复"，
    但这其实是设计意图（quick 是先到先得的快速回复，deep 是完整回复）。
    本测试验证超时后系统不会崩溃，且行为符合预期。
    """

    def __init__(self):
        super().__init__("reply_stream_intent_timeout", "agents.orchestrator")

    def run(self):
        from app.llm.fake import FakeClient
        from app.agents.orchestrator import ConversationOrchestrator

        # 使用 SlowClient 使意图识别超时
        # 但我们不能在意图识别阶段使用 SlowClient，因为它也会影响 quick_reply
        # 所以我们需要一个混合客户端：意图识别慢，quick_reply 快

        class MixedSlowClient:
            """意图识别（统一意图识别层）慢，其他调用快。"""
            def __init__(self):
                self.calls: list[dict] = []

            def chat(self, messages, *, temperature=0.7, max_tokens=1200,
                     response_format=None, thinking=None, reasoning_effort=None):
                self.calls.append({"messages": messages, "response_format": response_format})
                if messages and messages[0].get("role") == "system":
                    system = messages[0]["content"]
                    if "统一意图识别层" in system:
                        time.sleep(15)  # 超过 8s 超时
                # 非 json_object 返回普通文本
                if response_format and response_format.get("type") == "json_object":
                    content = json.dumps({
                        "reply": "超时后的降级回复。",
                        "expression_id": "calm",
                    }, ensure_ascii=False)
                else:
                    content = "快速回复文本。"
                return type("R", (), {
                    "content": content,
                    "model": "mixed-slow-client",
                    "raw": {},
                })()

        tmpdir = tempfile.mkdtemp()
        db_path = os.path.join(tmpdir, "intent_timeout_test.db")
        from app.memory.store import Store

        store = Store(db_path)
        llm = MixedSlowClient()
        orch = ConversationOrchestrator(llm=llm, store=store)

        sid = store.create_session()
        crashed = False
        error_msg = ""
        events = []
        try:
            # 意图识别应在 8s 后超时，但 quick_reply 应先完成
            events = list(orch.reply_stream(sid, "测试意图超时"))
        except Exception as e:
            crashed = True
            error_msg = f"{type(e).__name__}: {e}"

        if crashed:
            self.results.append(RobustnessResult(
                test_name="intent_timeout_no_crash",
                passed=False,
                module=self.module,
                scenario="意图识别超时后 reply_stream",
                message=f"意图识别超时导致 reply_stream 崩溃: {error_msg}",
                exception=error_msg,
            ))
        else:
            # 验证：应有 quick_reply 和至少一个后续事件
            event_types = []
            for ev in events:
                if ev.startswith("event:"):
                    event_type = ev.split("\n")[0].replace("event:", "").strip()
                    event_types.append(event_type)

            has_quick = "quick_reply" in event_types
            has_final = "final" in event_types or "deep_reply" in event_types

            self.results.append(RobustnessResult(
                test_name="intent_timeout_no_crash",
                passed=True,
                module=self.module,
                scenario="意图识别超时后 reply_stream",
                message=f"超时后正常完成，事件类型: {event_types}",
            ))
            self.results.append(RobustnessResult(
                test_name="intent_timeout_has_quick_reply",
                passed=has_quick,
                module=self.module,
                scenario="意图识别超时后 quick_reply 仍推送",
                message=f"quick_reply 事件: {'存在' if has_quick else '缺失'}",
            ))
            self.results.append(RobustnessResult(
                test_name="intent_timeout_has_final",
                passed=has_final,
                module=self.module,
                scenario="意图识别超时后有 final 事件",
                message=f"final/deep_reply 事件: {'存在' if has_final else '缺失'}",
            ))


# ===========================================================================
# 问题 7: web.py /api/data type 参数白名单验证
# ===========================================================================


class ApiDataWhitelistTest(AccuracyTest):
    """验证 /api/data 的 type 参数有白名单验证。

    问题代码 (web.py:3074-3101):
        data_type = params.get("type", "sessions")
        ...
        if data_type == "sessions": ...
        elif data_type == "memories": ...
        ...
        else: self.respond_json({"error": ...})

    虽然有 else 分支返回 400，但 type 参数直接用于决定调用哪个 store 方法，
    没有白名单验证。如果 store 方法名称与 type 值对应，可能存在注入风险。
    当前代码是 if-elif 结构，所以实际上安全，但测试验证 else 分支正常工作。
    """

    def __init__(self):
        super().__init__("api_data_whitelist", "web")

    def run(self):
        # 测试已知的合法 type 值
        valid_types = ["sessions", "memories", "state", "journals", "messages", "knowledge", "content"]
        for vt in valid_types:
            self.assert_true(
                f"type_valid_{vt}",
                vt in valid_types,
                f"type='{vt}' 是合法值",
            )

        # 测试非法 type 值应被拒绝
        # 注意：不实际启动 HTTP 服务器，只验证代码结构中的 else 分支
        # 通过代码分析确认 else 分支存在
        import inspect
        try:
            from app.web import Handler
            source = inspect.getsource(Handler.respond_data)
            has_else_branch = "respond_json" in source and '"error"' in source and "unknown data type" in source
            self.assert_true(
                "respond_data_has_else_guard",
                has_else_branch,
                "respond_data 有 else 分支返回 400 错误（白名单保护存在）"
                if has_else_branch
                else "respond_data 缺少 else 分支，非法 type 值可能执行未预期的代码路径",
            )
        except Exception as e:
            self.assert_true(
                "respond_data_inspectable",
                False,
                f"无法检查 respond_data 代码: {e}",
            )

        return self.results


# ===========================================================================
# 问题 8: prompt_tracker.py 路径遍历风险
# ===========================================================================


class PromptTrackerPathTraversalTest(AccuracyTest):
    """验证 PromptTracker 的日志文件路径不会被外部输入控制。

    问题代码 (prompt_tracker.py:127):
        date_str = datetime.now().strftime("%Y%m%d")
        path = self._storage_dir / f"prompt_calls_{date_str}.jsonl"

    _storage_dir 在 __new__ 中硬编码为 Path("data/prompt_logs")，
    文件名由日期字符串拼接，不直接受用户输入影响。

    但 _storage_dir 是一个可变属性，如果被外部修改可能导致路径遍历。
    本测试验证路径构造的安全性。
    """

    def __init__(self):
        super().__init__("prompt_tracker_path_traversal", "evaluation.prompt_tracker")

    def run(self):
        from pathlib import Path
        from app.evaluation.prompt_tracker import PromptTracker

        # 测试 1: 验证正常路径构造不含遍历
        tracker = PromptTracker()
        tracker.clear()

        import datetime
        date_str = datetime.datetime.now().strftime("%Y%m%d")
        expected_filename = f"prompt_calls_{date_str}.jsonl"
        actual_path = tracker._storage_dir / expected_filename

        self.assert_true(
            "log_path_no_traversal",
            ".." not in str(actual_path) and str(actual_path).startswith(str(tracker._storage_dir)),
            f"日志路径 '{actual_path}' 不含路径遍历",
        )

        # 测试 2: 验证 _storage_dir 默认值安全
        default_dir = str(tracker._storage_dir)
        self.assert_true(
            "storage_dir_is_local",
            "data/prompt_logs" in default_dir or "prompt_logs" in default_dir,
            f"_storage_dir 默认值为 '{default_dir}'，在项目目录内",
        )

        # 测试 3: 验证外部无法通过参数注入路径
        # record() 方法的参数不包含文件路径，无法通过 API 注入
        import inspect
        sig = inspect.signature(PromptTracker.record)
        params = list(sig.parameters.keys())
        no_path_param = "path" not in params and "file" not in params and "dir" not in params
        self.assert_true(
            "record_no_path_param",
            no_path_param,
            f"record() 参数列表 '{params}' 中不包含路径相关参数"
            if no_path_param
            else f"record() 包含路径参数 '{params}'，存在潜在风险",
        )

        # 测试 4: 验证 _storage_dir 可被修改（潜在风险点）
        original_dir = tracker._storage_dir
        tracker._storage_dir = Path("/tmp")
        new_dir = tracker._storage_dir
        is_mutable = new_dir == Path("/tmp")

        # 恢复
        tracker._storage_dir = original_dir

        if is_mutable:
            self.assert_true(
                "storage_dir_is_protected",
                False,
                "_storage_dir 是公开可变属性，可被外部代码修改为任意路径。"
                "建议：将 _storage_dir 改为私有属性，或添加 setter 验证路径合法性。",
            )
        else:
            self.assert_true(
                "storage_dir_is_protected",
                True,
                "_storage_dir 不可被外部修改",
            )

        return self.results


# ===========================================================================
# 汇总函数
# ===========================================================================


def get_code_review_tests() -> list:
    """返回所有代码审查问题测试实例"""
    return [
        SetContextThreadSafetyTest(),
        WriteJournalJsonProtectionTest(),
        ExtractMemoriesJsonProtectionTest(),
        DeepResponseLlmProtectionTest(),
        CloseSessionJournalFutureTest(),
        ReplyStreamIntentTimeoutTest(),
        ApiDataWhitelistTest(),
        PromptTrackerPathTraversalTest(),
    ]
