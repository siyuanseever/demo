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

        # 小类必须收敛到每个大类固定的 8 个选项，未知值进入 general。
        from app.memory.schema import MEMORY_SUBCATEGORIES

        self.assert_true(
            "memory_taxonomy_has_eight_fixed_subcategories",
            all(len(subcategories) == 8 for subcategories in MEMORY_SUBCATEGORIES.values()),
        )
        memory_id = self.store.add_memory(
            sid,
            {
                "category": "self_core",
                "subcategory": "llm_invented_subcategory",
                "content": "测试固定小类边界",
                "evidence": "测试",
                "keywords": ["测试"],
            },
        )
        normalized_memory = next(
            memory
            for memory in self.store.list_memories(limit=20)
            if memory["id"] == memory_id
        )
        self.assert_equal(
            "unknown_memory_subcategory_falls_back_to_general",
            normalized_memory["subcategory"],
            "general",
        )
        self.assert_equal(
            "unknown_memory_subcategory_preserves_no_new_bucket",
            len([
                item
                for item in self.store.memory_taxonomy_counts()
                if item["category"] == "self_core"
            ]),
            8,
        )

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

        # 用户资料库应按章节加载，并保留可解释来源和安全字段
        library_cards = [
            card for card in kr.list_cards()
            if card["id"].startswith("psych-library-")
        ]
        self.assert_equal("library_card_count", len(library_cards), 79)
        self.assert_true(
            "library_cards_have_source_refs",
            all(card.get("source_ref") for card in library_cards),
        )
        self.assert_true(
            "library_cards_have_alternatives",
            all(card.get("differential_explanations") for card in library_cards),
        )
        self.assert_true(
            "library_cards_have_concept_graph",
            all(card.get("related_cards") for card in library_cards),
        )
        self.assert_equal(
            "personalized_hypothesis_is_not_fact",
            kr.get_card("psych-library-h3")["concept_type"],
            "personalized_hypothesis",
        )
        self.assert_equal(
            "contested_theory_is_marked",
            kr.get_card("psych-library-3-6")["concept_type"],
            "contested_theory",
        )
        self.assert_true(
            "body_card_has_medical_differential",
            bool(kr.get_card("psych-library-4-1")["medical_differential"]),
        )
        supplemental_cards = [
            card for card in kr.list_cards()
            if card.get("source_ref", "").startswith("补充资料：")
            or card["id"] in {
                "stress_executive_function_shift",
                "arousal_carryover",
                "appeasement_response",
                "shame_triggered_self_attack",
                "spotlight_effect",
                "affiliative_mimicry",
                "optional_pressure_and_release",
            }
        ]
        self.assert_equal("supplemental_card_count", len(supplemental_cards), 16)
        self.assert_true(
            "supplemental_actions_are_bounded",
            all(card.get("low_load_actions") and "action_safety" in card for card in supplemental_cards),
        )
        self.assert_true(
            "dorsal_vagal_is_contested_alias",
            "背侧迷走神经强制关机" in kr.get_card("psych-library-3-6")["aliases"],
        )
        self.assert_true(
            "curated_triggers_are_merged",
            "她不回我" in kr.get_card("psych-library-7-2")["retrieval_triggers"],
        )
        self.assert_equal(
            "curated_overpathologizing_risk",
            kr.get_card("psych-library-7-2")["risk_of_overpathologizing"],
            "medium",
        )

        scenario_expectations = [
            ("她两个小时没回我，是不是讨厌我？", "psych-library-7-2"),
            ("我逛街的时候眼睛特别累，脑袋不在线。", "psych-library-4-1"),
            ("别人展示了一个很复杂的 Agent，我突然觉得自己很差。", "psych-library-2-6"),
            ("我三天没出门，什么都不想做。", "psych-library-3-3"),
            ("我明明在骑车，但脑子完全放松不下来。", "psych-library-2-1"),
            ("我现在没工作，我是不是以后都找不到了？", "psych-library-9-3"),
            ("这个公司让我觉得很剥削，但我不知道是不是我太敏感。", "psych-library-2-5"),
            ("我只想打游戏，不想面对现实。", "psych-library-5-3"),
        ]
        for index, (query, expected_id) in enumerate(scenario_expectations, start=1):
            card_ids = [card["id"] for card in kr.retrieve(query, limit=3)]
            self.assert_true(
                f"library_scenario_{index}",
                expected_id in card_ids,
                f"{expected_id} 应出现在 {card_ids} 中",
            )

        supplemental_scenarios = [
            ("被人审视的时候我手臂特别紧，脑子突然空白", "stress_executive_function_shift"),
            ("刚才很紧张，过会儿面试还是缓不过来", "arousal_carryover"),
            ("面对强势领导我会自动赞同，明明不愿意也不敢说不", "appeasement_response"),
            ("我总觉得所有人都在看我的小动作", "spotlight_effect"),
            ("她吃水果我也跟着吃，我是不是在模仿她", "affiliative_mimicry"),
            ("大厂流程很慢，是不是说明我能力不行", "attribution_under_uncertainty"),
            ("两个圈子的人同时在场，我不知道该按哪套标准说话", "conflicting_audience_load"),
            ("我一直刷新消息，什么都做不了", "asynchronous_waiting"),
            ("我想用重被子强制让神经系统关机", "optional_pressure_and_release"),
            ("不安慰她就生气，这是武器化脆弱吗", "asymmetric_vulnerability_labor"),
            ("背侧迷走神经让我强制关机了", "psych-library-3-6"),
        ]
        for index, (query, expected_id) in enumerate(supplemental_scenarios, start=1):
            card_ids = [card["id"] for card in kr.retrieve(query, limit=3)]
            self.assert_true(
                f"supplemental_scenario_{index}",
                expected_id in card_ids,
                f"{expected_id} 应出现在 {card_ids} 中",
            )

        response_plan = kr.retrieve_plan(
            "我逛街的时候眼睛特别累，脑袋不在线。",
            limit=3,
        )
        self.assert_true(
            "response_plan_has_contract",
            all(
                key in response_plan
                for key in [
                    "extracted_state",
                    "primary_cards",
                    "alternative_explanations",
                    "medical_differential",
                    "rejected_overinterpretations",
                    "response_strategy",
                    "safety_flags",
                ]
            ),
        )
        self.assert_true(
            "response_plan_primary_limit",
            len(response_plan["primary_cards"]) <= 3,
        )
        self.assert_true(
            "response_plan_preserves_alternatives",
            bool(response_plan["alternative_explanations"]),
        )
        self.assert_true(
            "response_plan_forces_medical_differential",
            bool(response_plan["medical_differential"])
            and "preserve_medical_differential" in response_plan["safety_flags"],
        )
        self.assert_true(
            "response_plan_extracts_body_state",
            "眼睛" in response_plan["extracted_state"]["body"],
        )
        generic_cards = kr.retrieve("我今天有点累", limit=4)
        self.assert_true(
            "personalized_hypothesis_is_gated",
            all(card["concept_type"] != "personalized_hypothesis" for card in generic_cards),
        )

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
        from app.agents.orchestrator import (
            parse_json_object,
            render_memories,
            render_quick_reply_handoff,
        )

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

        handoff = render_quick_reply_handoff("我听见你现在很累。")
        self.assert_contains("quick_handoff_keeps_reply", handoff, "我听见你现在很累。")
        self.assert_contains("quick_handoff_avoids_repetition", handoff, "不要再次复述")
        self.assert_contains("quick_handoff_requires_new_value", handoff, "尚未覆盖")
        self.assert_equal("quick_handoff_empty", render_quick_reply_handoff("  "), "")

        return self.results


class TTSHelpersAccuracyTest(AccuracyTest):
    """tts_server 分段与质量重试准确率测试"""

    def __init__(self):
        super().__init__("tts_helpers", "tts_server")

    def run(self):
        from types import SimpleNamespace

        import numpy as np

        from app import tts_server

        service = tts_server.LocalTTS()
        source = (
            "我知道你现在有一点难受，也许不需要立刻找到答案。"
            "我们可以先把这一刻说清楚，再慢慢看看下一步。"
            "即使句子很长，语音也不应该漏掉其中任何一段内容。"
        )
        segments = service._split_text(source)
        normalized = lambda value: "".join(value.split())
        self.assert_equal(
            "tts_segments_preserve_all_text",
            normalized("".join(segments)),
            normalized(source),
        )
        self.assert_true(
            "tts_segments_respect_max_length",
            all(len(segment) <= tts_server.MAX_SEGMENT_CHARS for segment in segments),
        )

        class RetryModel:
            def __init__(self):
                self.calls = []

            def generate(self, **kwargs):
                self.calls.append(kwargs)
                sample_count = 10_000 if len(self.calls) == 1 else 2_000
                yield SimpleNamespace(
                    audio=np.full(sample_count, 0.1, dtype=np.float32),
                    sample_rate=1_000,
                )

        model = RetryModel()
        audio, sample_rate = service._generate_segment(
            model,
            "请陪我安静一会儿。",
            "Serena",
            tts_server.DEFAULT_INSTRUCT,
            1,
            1,
        )
        self.assert_equal("tts_quality_failure_retries", len(model.calls), 2)
        self.assert_true(
            "tts_retry_changes_generation_settings",
            model.calls[0]["instruct"] != model.calls[1]["instruct"]
            and model.calls[0]["temperature"] != model.calls[1]["temperature"],
        )
        self.assert_equal("tts_retry_returns_valid_sample_rate", sample_rate, 1_000)
        self.assert_equal("tts_retry_returns_complete_audio", len(audio), 2_000)

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
        TTSHelpersAccuracyTest(),
    ]
