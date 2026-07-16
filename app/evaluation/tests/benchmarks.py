"""
耗时基准测试

对各核心模块进行调用耗时统计。
"""

import time
import tempfile
import os
from app.evaluation.timer import Timer, timed


def benchmark_memory_store() -> list[dict]:
    """测试 memory.store 模块耗时"""
    from app.memory.store import Store
    timer = Timer()

    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test.db")
        store = Store(db_path)

        # benchmark create_session
        session_ids = []
        for _ in range(20):
            with timed("memory.store.create_session", timer):
                sid = store.create_session()
                session_ids.append(sid)

        # benchmark add_message
        for i, sid in enumerate(session_ids[:10]):
            with timed("memory.store.add_message", timer):
                store.add_message(sid, "user", f"test message {i}")

        # benchmark get_session_messages
        for sid in session_ids[:10]:
            with timed("memory.store.get_session_messages", timer):
                store.get_session_messages(sid)

        # benchmark list_sessions
        with timed("memory.store.list_sessions", timer):
            store.list_sessions(limit=50)

        # benchmark search_memories (empty db)
        with timed("memory.store.search_memories", timer):
            store.search_memories("test", limit=5)

    return timer.summary()


def benchmark_knowledge_retriever() -> list[dict]:
    """测试 knowledge.retriever 模块耗时"""
    from app.knowledge.retriever import KnowledgeRetriever
    timer = Timer()

    kr = KnowledgeRetriever()

    queries = [
        "焦虑",
        "睡眠问题",
        "工作压力",
        "人际关系",
        "",
        "a" * 500,
    ]

    for q in queries:
        with timed("knowledge.retriever.retrieve", timer):
            kr.retrieve(q, limit=3)

    return timer.summary()


def benchmark_characters() -> list[dict]:
    """测试 characters 模块耗时"""
    from app.characters import get_character, auto_select_character, CHARACTERS
    timer = Timer()

    for char_id in list(CHARACTERS.keys())[:5]:
        with timed("characters.get_character", timer):
            get_character(char_id)

    texts = ["", "hello", "焦虑", "开心", "a" * 1000, "12345"]
    for text in texts:
        with timed("characters.auto_select_character", timer):
            auto_select_character(text)

    return timer.summary()


def benchmark_safety() -> list[dict]:
    """测试 safety 模块耗时"""
    from app.agents.safety import detect_crisis
    timer = Timer()

    texts = [
        "今天天气不错",
        "我想结束这一切",
        "",
        "a" * 2000,
        "自杀 死亡 结束生命",
        "很开心",
    ]

    for text in texts:
        with timed("safety.detect_crisis", timer):
            detect_crisis(text)

    return timer.summary()


def benchmark_llm_base() -> list[dict]:
    """测试 llm.base 模块耗时"""
    from app.llm.base import LLMResponse, Message
    timer = Timer()

    for i in range(50):
            with timed("llm.base.LLMResponse_creation", timer):
                LLMResponse(content=f"test {i}", model="fake", raw={})

    return timer.summary()


def benchmark_orchestrator_helpers() -> list[dict]:
    """测试 orchestrator 辅助函数耗时"""
    from app.agents.orchestrator import parse_json_object, render_memories, render_state_profiles
    timer = Timer()

    json_texts = [
        '{"a": 1}',
        "```json\n{\"b\": 2}\n```",
        "{\"c\": 3}",
        "invalid",
        "",
    ]
    for text in json_texts:
        with timed("orchestrator.parse_json_object", timer):
            try:
                parse_json_object(text)
            except Exception:
                pass

    memories = [
        {"category": "emotion", "subcategory": "anxiety", "content": "感到焦虑", "evidence": "用户说很焦虑", "keywords": '["焦虑"]'},
    ] * 10
    with timed("orchestrator.render_memories", timer):
        render_memories(memories)

    profiles = [
        {"domain": "emotion", "stage": "波动", "summary": "情绪波动", "intensity": 6, "trend": "stable", "confidence": 0.7, "support_strategy": "陪伴", "evidence": ["对话记录"]},
    ] * 5
    with timed("orchestrator.render_state_profiles", timer):
        render_state_profiles(profiles)

    return timer.summary()


def run_all_benchmarks() -> list[dict]:
    """运行所有耗时基准测试并汇总"""
    from app.evaluation.timer import Timer
    Timer().reset()  # 清空单例中的历史数据，避免重复
    all_stats = []

    benchmarks = [
        benchmark_memory_store,
        benchmark_knowledge_retriever,
        benchmark_characters,
        benchmark_safety,
        benchmark_llm_base,
        benchmark_orchestrator_helpers,
    ]

    for bench in benchmarks:
        try:
            stats = bench()
            all_stats.extend(stats)
        except Exception as e:
            print(f"   基准测试 {bench.__name__} 失败: {e}")

    return all_stats
