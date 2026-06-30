"""
鲁棒性测试用例

测试系统在边界条件、异常输入、并发场景下的稳定性。
"""

import tempfile
import os

from app.evaluation.robustness import RobustnessTest


class MemoryStoreRobustnessTest(RobustnessTest):
    """memory.store 鲁棒性测试"""

    def __init__(self):
        super().__init__("memory_store", "memory.store")
        self.tmpdir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmpdir, "rob_test.db")
        from app.memory.store import Store
        self.store = Store(self.db_path)

    def run(self):
        # 边界: 空 session_id
        self.test_edge_case("empty_session_id", self.store.get_session, "")

        # 边界: 超长内容
        self.test_edge_case("long_message_content", self.store.add_message,
                           self.store.create_session(), "user", "x" * 100000)

        # 边界: 特殊字符
        sid = self.store.create_session()
        self.test_edge_case("special_chars_message", self.store.add_message,
                           sid, "user", "<script>alert(1)</script>\n\t\\\"'\"")

        # 边界: 空消息内容
        self.test_edge_case("empty_message_content", self.store.add_message,
                           sid, "user", "")

        # 并发: 同时创建多个 session
        self.test_concurrent("concurrent_create_session",
                            self.store.create_session,
                            [()] * 20,
                            max_workers=10)

        # 压力: 连续添加消息
        sid = self.store.create_session()
        self.test_stress("stress_add_message",
                        self.store.add_message,
                        iterations=50,
                        args=(sid, "user", "stress test"))

        # 边界: 搜索异常查询
        self.test_edge_case("search_empty", self.store.search_memories, "", limit=5)
        self.test_edge_case("search_special_chars", self.store.search_memories, "!@#$%", limit=5)

        return self.results


class CharactersRobustnessTest(RobustnessTest):
    """characters 模块鲁棒性测试"""

    def __init__(self):
        super().__init__("characters", "characters")

    def run(self):
        from app.characters import get_character, auto_select_character

        # 边界: None / 空字符串
        self.test_edge_case("get_character_none", get_character, None)
        self.test_edge_case("get_character_empty", get_character, "")
        self.test_edge_case("auto_select_empty", auto_select_character, "")

        # 边界: 超长字符串
        self.test_edge_case("auto_select_long", auto_select_character, "x" * 10000)

        # 边界: 特殊字符
        self.test_edge_case("auto_select_special", auto_select_character, "!@#$%^&*()")

        # 并发: 同时获取角色
        self.test_concurrent("concurrent_get_character",
                            get_character,
                            [("mianmian-sheep",), ("youyou-rabbit",), ("gangan-tiger",)] * 10,
                            max_workers=10)

        return self.results


class SafetyRobustnessTest(RobustnessTest):
    """safety 模块鲁棒性测试"""

    def __init__(self):
        super().__init__("safety", "agents.safety")

    def run(self):
        from app.agents.safety import detect_crisis

        # 边界: 空输入
        self.test_edge_case("detect_empty", detect_crisis, "")

        # 边界: 超长输入
        self.test_edge_case("detect_long", detect_crisis, "x" * 50000)

        # 边界: 特殊字符
        self.test_edge_case("detect_special", detect_crisis, "!@#$%^&*()\n\t")

        # 压力: 连续检测
        self.test_stress("stress_detect_crisis",
                        detect_crisis,
                        iterations=200,
                        args=("今天天气不错",))

        return self.results


class KnowledgeRobustnessTest(RobustnessTest):
    """knowledge 模块鲁棒性测试"""

    def __init__(self):
        super().__init__("knowledge", "knowledge.retriever")

    def run(self):
        from app.knowledge.retriever import KnowledgeRetriever

        kr = KnowledgeRetriever()

        # 边界: 空查询
        self.test_edge_case("retrieve_empty", kr.retrieve, "", limit=3)

        # 边界: 超长查询
        self.test_edge_case("retrieve_long", kr.retrieve, "x" * 10000, limit=3)

        # 边界: 特殊字符
        self.test_edge_case("retrieve_special", kr.retrieve, "<script>alert(1)</script>", limit=3)

        # 边界: 负 limit
        self.test_edge_case("retrieve_negative_limit", kr.retrieve, "test", limit=-1)

        # 并发: 同时检索 (limit 是 keyword-only 参数)
        self.test_concurrent("concurrent_retrieve",
                            lambda q, l: kr.retrieve(q, limit=l),
                            [("焦虑", 3), ("睡眠", 3), ("压力", 3)] * 10,
                            max_workers=10)

        return self.results


class OrchestratorHelpersRobustnessTest(RobustnessTest):
    """orchestrator 辅助函数鲁棒性测试"""

    def __init__(self):
        super().__init__("orchestrator_helpers", "agents.orchestrator")

    def run(self):
        from app.agents.orchestrator import parse_json_object, render_memories, render_state_profiles

        # 边界: 无效 JSON
        self.test_edge_case("parse_invalid_json", parse_json_object, "not json")

        # 边界: 空字符串
        self.test_edge_case("parse_empty", parse_json_object, "")

        # 边界: 超长 JSON
        self.test_edge_case("parse_long_json", parse_json_object, '{"a": "' + "x" * 10000 + '"}')

        # 边界: 空列表渲染
        self.test_edge_case("render_empty_memories", render_memories, [])
        self.test_edge_case("render_empty_profiles", render_state_profiles, [])

        # 边界: 异常格式的 memories
        bad_memories = [
            {"category": "x", "subcategory": "y", "content": "z", "evidence": "e", "keywords": "not a list"},
        ]
        self.test_edge_case("render_bad_keywords", render_memories, bad_memories)

        return self.results


def get_robustness_tests() -> list[RobustnessTest]:
    """返回所有鲁棒性测试实例"""
    return [
        MemoryStoreRobustnessTest(),
        CharactersRobustnessTest(),
        SafetyRobustnessTest(),
        KnowledgeRobustnessTest(),
        OrchestratorHelpersRobustnessTest(),
    ]
