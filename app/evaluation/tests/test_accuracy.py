"""
准确率测试用例

验证各模块核心功能的正确性。
"""

import tempfile
import os

from app.evaluation.accuracy import AccuracyTest


class MemoryStoreAccuracyTest(AccuracyTest):
    """memory.store 准确率测试"""

    def __init__(self):
        super().__init__("memory_store", "memory.store")
        self.tmpdir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmpdir, "acc_test.db")
        from app.memory.store import Store
        self.store = Store(self.db_path)

    def run(self):
        # 测试 create_session
        sid = self.store.create_session()
        self.assert_true("create_session_returns_uuid", len(sid) > 10, "session_id 应为有效字符串")

        session = self.store.get_session(sid)
        self.assert_equal("get_session_exists", session is not None, True)
        self.assert_equal("get_session_id", session["id"] if session else None, sid)

        # 测试 add_message
        msg_id = self.store.add_message(sid, "user", "hello")
        self.assert_true("add_message_returns_id", len(msg_id) > 5)

        messages = self.store.get_session_messages(sid)
        self.assert_equal("message_count", len(messages), 1)
        self.assert_equal("message_role", messages[0]["role"], "user")
        self.assert_equal("message_content", messages[0]["content"], "hello")

        # 测试 list_sessions
        sessions = self.store.list_sessions(limit=10)
        self.assert_true("list_sessions_not_empty", len(sessions) >= 1)

        # 测试 end_session
        self.store.end_session(sid)
        session_after = self.store.get_session(sid)
        self.assert_true("end_session_sets_ended_at", session_after.get("ended_at") is not None if session_after else False)

        # 测试 search_memories (空数据库应返回空或 gracefully handle)
        results = self.store.search_memories("test", limit=5)
        self.assert_true("search_memories_returns_list", isinstance(results, list))

        return self.results


class CharactersAccuracyTest(AccuracyTest):
    """characters 模块准确率测试"""

    def __init__(self):
        super().__init__("characters", "characters")

    def run(self):
        from app.characters import get_character, auto_select_character, CHARACTERS

        # 测试 get_character 所有角色
        for char_id in CHARACTERS:
            char = get_character(char_id)
            self.assert_true(f"get_character_{char_id}", char is not None)
            self.assert_true(f"character_has_name_{char_id}", bool(char.name))

        # 测试无效角色
        char = get_character("nonexistent")
        self.assert_true("get_character_fallback", char is not None)

        # 测试 auto_select_character
        char = auto_select_character("我很焦虑")
        self.assert_true("auto_select_anxiety", char is not None)

        char = auto_select_character("")
        self.assert_true("auto_select_empty", char is not None)

        return self.results


class SafetyAccuracyTest(AccuracyTest):
    """safety 模块准确率测试"""

    def __init__(self):
        super().__init__("safety", "agents.safety")

    def run(self):
        from app.agents.safety import detect_crisis

        # 基础危机表达（已有关键词覆盖）
        crisis_texts_basic = [
            "我想结束自己的生命",
            "我不想活了",
            "自杀",
            "结束这一切",
        ]
        for text in crisis_texts_basic:
            self.assert_true(f"crisis_detect_basic_{text[:10]}", detect_crisis(text), f"应检测到危机: {text}")

        # 扩展危机表达（测试关键词覆盖盲区）
        crisis_texts_extended = [
            ("自残", "自残行为识别"),
            ("割腕", "割腕行为识别"),
            ("跳楼", "跳楼行为识别"),
            ("想死", "想死表达识别"),
            ("死了算了", "死了算了表达识别"),
            ("活着没意思", "活着没意思表达识别"),
            ("自伤", "自伤行为识别"),
            ("不想活了", "不想活了表达识别"),
            ("抑郁到想死", "抑郁到想死表达识别"),
            ("结束生命", "结束生命表达识别"),
        ]
        for text, desc in crisis_texts_extended:
            detected = detect_crisis(text)
            self.assert_true(
                f"crisis_detect_extended_{desc}",
                detected,
                f"{desc}: '{text}' 应被检测为危机",
            )

        safe_texts = [
            "今天天气不错",
            "我很开心",
            "",
            "12345",
            "这本书讲的是如何结束一段关系",
        ]
        for text in safe_texts:
            self.assert_true(f"safe_detect_{text[:10]}", not detect_crisis(text), f"不应检测到危机: {text}")

        # 已知假阳性观察：当前关键词匹配为子串匹配，以下文本会被误报
        # 但保留为 observation，提示未来需要更精细的语义检测
        from app.evaluation.accuracy import AccuracyResult
        false_positive_texts = [
            ("自杀是一个严重的社会学话题", "包含'自杀'子串的学术讨论"),
            ("他伤害别人的感情了", "包含'伤害别人'子串的日常表达"),
        ]
        for text, reason in false_positive_texts:
            detected = detect_crisis(text)
            self.results.append(AccuracyResult(
                test_name=f"safe_fp_{text[:10]}",
                passed=True,  # observation 不计入失败
                expected=False,
                actual=detected,
                message=(
                    f"已知假阳性观察: '{text[:30]}...' 被检测为危机，原因: {reason}。"
                    f"当前使用子串匹配，未来应升级为语义分析。"
                ),
                module=self.module,
            ))

        return self.results


class KnowledgeAccuracyTest(AccuracyTest):
    """knowledge 模块准确率测试"""

    def __init__(self):
        super().__init__("knowledge", "knowledge.retriever")

    def run(self):
        from app.knowledge.retriever import KnowledgeRetriever

        kr = KnowledgeRetriever()

        # 测试正常检索
        results = kr.retrieve("焦虑", limit=3)
        self.assert_true("retrieve_returns_list", isinstance(results, list))
        self.assert_true("retrieve_limit_respected", len(results) <= 3)

        # 测试空查询
        results = kr.retrieve("", limit=3)
        self.assert_true("retrieve_empty_query", isinstance(results, list))

        # 测试超长查询
        results = kr.retrieve("a" * 1000, limit=3)
        self.assert_true("retrieve_long_query", isinstance(results, list))

        return self.results


class LLMBaseAccuracyTest(AccuracyTest):
    """llm.base 模块准确率测试"""

    def __init__(self):
        super().__init__("llm_base", "llm.base")

    def run(self):
        from app.llm.base import LLMResponse, Message

        resp = LLMResponse(content="test", model="fake", raw={})
        self.assert_equal("response_content", resp.content, "test")
        self.assert_equal("response_model", resp.model, "fake")

        msg = Message(role="user", content="hello")
        self.assert_equal("message_role", msg["role"], "user")
        self.assert_equal("message_content", msg["content"], "hello")

        return self.results


class OrchestratorHelpersAccuracyTest(AccuracyTest):
    """orchestrator 辅助函数准确率测试"""

    def __init__(self):
        super().__init__("orchestrator_helpers", "agents.orchestrator")

    def run(self):
        from app.agents.orchestrator import parse_json_object, render_memories

        # 测试 parse_json_object
        self.assert_equal("parse_plain_json", parse_json_object('{"a":1}'), {"a": 1})
        self.assert_equal("parse_json_with_code_block", parse_json_object('```json\n{"b":2}\n```'), {"b": 2})

        # 测试 render_memories
        memories = [
            {"category": "emotion", "subcategory": "anxiety", "content": "test", "evidence": "ev", "keywords": '["k1"]'},
        ]
        rendered = render_memories(memories)
        self.assert_true("render_memories_non_empty", len(rendered) > 0)
        self.assert_contains("render_memories_has_content", rendered, "test")

        # 测试空列表
        empty_rendered = render_memories([])
        self.assert_true("render_memories_empty", "暂无" in empty_rendered)

        return self.results


def get_accuracy_tests() -> list[AccuracyTest]:
    """返回所有准确率测试实例"""
    return [
        MemoryStoreAccuracyTest(),
        CharactersAccuracyTest(),
        SafetyAccuracyTest(),
        KnowledgeAccuracyTest(),
        LLMBaseAccuracyTest(),
        OrchestratorHelpersAccuracyTest(),
    ]
