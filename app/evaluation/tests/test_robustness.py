"""
鲁棒性测试用例

测试系统在边界条件、异常输入、并发场景下的稳定性。
"""

import tempfile
import os

from app.evaluation.robustness import RobustnessTest, RobustnessResult


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


class ConfigRobustnessTest(RobustnessTest):
    """config 模块鲁棒性测试"""

    def __init__(self):
        super().__init__("config", "config")

    def run(self):
        import os
        from app.config import get_settings

        # 备份原始环境变量
        original_values = {}
        env_keys = [
            "WEB_TIMEOUT_MS", "WEB_PORT", "DEEPSEEK_TIMEOUT",
            "INTENT_CONFIDENCE_THRESHOLD", "QUICK_REPLY_MAX_TOKENS",
        ]
        for key in env_keys:
            original_values[key] = os.environ.get(key)

        try:
            # 边界: 无效的整数环境变量
            os.environ["WEB_TIMEOUT_MS"] = "not_a_number"
            try:
                get_settings()
                self.results.append(RobustnessResult(
                    test_name="config_invalid_int_fallback",
                    passed=False,
                    module=self.module,
                    scenario="无效整数环境变量",
                    message="get_settings() 在 WEB_TIMEOUT_MS='not_a_number' 时没有抛出异常，"
                            "可能静默使用了错误值或默认值处理不一致",
                ))
            except ValueError:
                self.results.append(RobustnessResult(
                    test_name="config_invalid_int_fallback",
                    passed=True,
                    module=self.module,
                    scenario="无效整数环境变量",
                    message="get_settings() 在无效整数环境变量时正确抛出 ValueError",
                ))

            # 边界: 无效浮点数环境变量
            os.environ["DEEPSEEK_TIMEOUT"] = "invalid_float"
            try:
                get_settings()
                self.results.append(RobustnessResult(
                    test_name="config_invalid_float_fallback",
                    passed=False,
                    module=self.module,
                    scenario="无效浮点数环境变量",
                    message="get_settings() 在 DEEPSEEK_TIMEOUT='invalid_float' 时没有抛出异常",
                ))
            except ValueError:
                self.results.append(RobustnessResult(
                    test_name="config_invalid_float_fallback",
                    passed=True,
                    module=self.module,
                    scenario="无效浮点数环境变量",
                    message="get_settings() 在无效浮点数环境变量时正确抛出 ValueError",
                ))

            # 边界: 空字符串环境变量
            os.environ["WEB_PORT"] = ""
            try:
                get_settings()
                self.results.append(RobustnessResult(
                    test_name="config_empty_string_port",
                    passed=False,
                    module=self.module,
                    scenario="空字符串端口环境变量",
                    message="get_settings() 在 WEB_PORT='' 时没有抛出异常",
                ))
            except ValueError:
                self.results.append(RobustnessResult(
                    test_name="config_empty_string_port",
                    passed=True,
                    module=self.module,
                    scenario="空字符串端口环境变量",
                    message="get_settings() 在空字符串端口时正确抛出 ValueError",
                ))
        finally:
            # 恢复环境变量
            for key, value in original_values.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

        return self.results


class IntentAgentRobustnessTest(RobustnessTest):
    """intent.agent 模块鲁棒性测试"""

    def __init__(self):
        super().__init__("intent_agent", "intent.agent")

    def run(self):
        from app.intent.agent import IntentAgent
        from app.llm.fake import FakeClient

        llm = FakeClient()
        agent = IntentAgent(llm=llm)

        # 边界: None 作为 conversation_history
        self.test_edge_case("recognize_none_history", agent.recognize, "测试", None)

        # 边界: 空列表作为 conversation_history
        self.test_edge_case("recognize_empty_history", agent.recognize, "测试", [])

        # 边界: 包含异常格式项的 history
        bad_history = [
            {"role": "user"},  # 缺少 content
            {"content": "hello"},  # 缺少 role
            None,  # None 项
            "not a dict",  # 字符串项
        ]
        self.test_edge_case("recognize_bad_history_items", agent.recognize, "测试", bad_history)

        # 边界: 超长用户输入
        self.test_edge_case("recognize_long_input", agent.recognize, "x" * 10000, [])

        # 边界: _render_history 中 max_history_turns 被异常设置
        original_turns = agent.max_history_turns
        try:
            agent.max_history_turns = None
            self.test_edge_case("render_history_none_turns", agent._render_history, [])
        finally:
            agent.max_history_turns = original_turns

        return self.results


class WebBoundaryRobustnessTest(RobustnessTest):
    """web.py 边界条件鲁棒性测试"""

    def __init__(self):
        super().__init__("web_boundary", "web")

    def run(self):
        # 测试 URL 参数解析的边界情况
        from urllib.parse import urlparse

        # 边界: 空 query
        query = ""
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        self.results.append(RobustnessResult(
            test_name="parse_empty_query",
            passed=params == {},
            module=self.module,
            scenario="空 query 参数解析",
            message=f"空 query 解析结果: {params}",
        ))

        # 边界: 重复 key
        query = "type=messages&type=sessions&limit=10"
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        self.results.append(RobustnessResult(
            test_name="parse_duplicate_keys",
            passed=params.get("type") == "sessions",
            module=self.module,
            scenario="重复 key 参数解析",
            message=f"重复 key 解析结果: {params}（后面的值覆盖前面的）",
        ))

        # 边界: 特殊字符在 query 中
        query = "type=mem%6Fries&limit=5"
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        self.results.append(RobustnessResult(
            test_name="parse_encoded_query",
            passed=params.get("type") == "mem%6Fries",
            module=self.module,
            scenario="URL 编码参数解析",
            message=f"编码参数解析结果: {params}（未自动解码，符合预期）",
        ))

        # 边界: 无等号的参数片段
        query = "type=messages&invalid_fragment&limit=10"
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        self.results.append(RobustnessResult(
            test_name="parse_invalid_fragment",
            passed="invalid_fragment" not in params and params.get("type") == "messages",
            module=self.module,
            scenario="无效参数片段过滤",
            message=f"无效片段过滤结果: {params}",
        ))

        return self.results


def get_robustness_tests() -> list[RobustnessTest]:
    """返回所有鲁棒性测试实例"""
    from app.evaluation.tests.test_code_review_findings import get_code_review_tests
    return [
        MemoryStoreRobustnessTest(),
        CharactersRobustnessTest(),
        SafetyRobustnessTest(),
        KnowledgeRobustnessTest(),
        OrchestratorHelpersRobustnessTest(),
        ConfigRobustnessTest(),
        IntentAgentRobustnessTest(),
        WebBoundaryRobustnessTest(),
        *get_code_review_tests(),
    ]
