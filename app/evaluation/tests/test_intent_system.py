"""
意图识别与路由系统测试

纯本地测试，不依赖任何 API 调用。
覆盖三大模块:
1. IntentAgent._normalize() —— 输入解析与归一化
2. IntentAgent._fallback_result() —— 失败回退
3. IntentRouter.decide() —— 路由决策逻辑
4. IntentRouter._to_route_plan() —— 与现有系统的兼容性
5. Schema 数据结构 —— 边界条件

运行方式:
    python3 -m app.evaluation.tests.test_intent_system
"""

import json
import time
import sys
import traceback
from pathlib import Path

# 确保项目根目录在路径中
sys.path.insert(0, str(Path(__file__).resolve().parents[4]))


class TestResult:
    def __init__(self, name: str, passed: bool, expected: str = "", actual: str = "", detail: str = ""):
        self.name = name
        self.passed = passed
        self.expected = expected
        self.actual = actual
        self.detail = detail
        self.elapsed_sec = 0.0


def run_test(name, func) -> TestResult:
    """运行单个测试"""
    start = time.monotonic()
    try:
        passed, expected, actual, detail = func()
        return TestResult(name, passed, expected, actual, detail)
    except Exception as e:
        return TestResult(name, False, "无异常", f"异常: {type(e).__name__}: {e}", traceback.format_exc())
    finally:
        pass


def check(cond, expected: str, actual: str, detail: str = ""):
    return (bool(cond), expected, actual, detail)


# ============================================================
# 1. IntentAgent._normalize() 测试
# ============================================================
def test_intent_agent_normalize():
    """测试 IntentAgent 的输入解析与归一化逻辑"""
    from app.intent.agent import IntentAgent
    from app.llm.fake import FakeClient

    llm = FakeClient()
    agent = IntentAgent(llm, confidence_threshold=0.85)
    results = []

    # 1.1 正常输入解析
    raw = {
        "intent": "QUICK_REPLY",
        "confidence": 0.92,
        "emotion": "平静",
        "risk_level": "low",
        "character_id": "yoyo",
        "expression_id": "calm",
        "response_mode": "validate",
        "memory_queries": ["焦虑", "睡眠"],
        "knowledge_queries": ["正念"],
        "user_state": "日常闲聊",
        "core_need": "陪伴",
        "response_guidance": "温柔回应",
        "reason": "用户在闲聊",
    }
    result = agent._normalize(raw)
    results.append(run_test("normalize: 正常输入", lambda: check(
        result.intent == "QUICK_REPLY"
        and result.confidence == 0.92
        and result.emotion == "平静"
        and result.risk_level == "low"
        and result.character_id == "yoyo"
        and result.memory_queries == ["焦虑", "睡眠"],
        "intent=QUICK_REPLY, confidence=0.92, risk=low",
        f"intent={result.intent}, conf={result.confidence}, risk={result.risk_level}",
    )))

    # 1.2 无效 intent 修正为 QUICK_REPLY
    raw2 = {"intent": "INVALID_TYPE", "confidence": 0.5}
    result2 = agent._normalize(raw2)
    results.append(run_test("normalize: 无效 intent 修正", lambda: check(
        result2.intent == "QUICK_REPLY",
        "QUICK_REPLY (默认值)",
        result2.intent,
    )))

    # 1.3 intent 大小写兼容
    raw3 = {"intent": "deep_reply", "confidence": 0.8}
    result3 = agent._normalize(raw3)
    results.append(run_test("normalize: intent 大小写兼容", lambda: check(
        result3.intent == "DEEP_REPLY",
        "DEEP_REPLY",
        result3.intent,
    )))

    # 1.4 confidence 超范围截断
    raw4 = {"intent": "QUICK_REPLY", "confidence": 1.5}
    result4 = agent._normalize(raw4)
    results.append(run_test("normalize: confidence 上限截断", lambda: check(
        result4.confidence == 1.0,
        "1.0",
        str(result4.confidence),
    )))

    raw5 = {"intent": "QUICK_REPLY", "confidence": -0.3}
    result5 = agent._normalize(raw5)
    results.append(run_test("normalize: confidence 下限截断", lambda: check(
        result5.confidence == 0.0,
        "0.0",
        str(result5.confidence),
    )))

    # 1.5 无效 risk_level 修正为 low
    raw6 = {"intent": "QUICK_REPLY", "confidence": 0.5, "risk_level": "critical"}
    result6 = agent._normalize(raw6)
    results.append(run_test("normalize: 无效 risk_level 修正", lambda: check(
        result6.risk_level == "low",
        "low",
        result6.risk_level,
    )))

    # 1.6 CLARIFY 时提取 clarify_reply
    raw7 = {"intent": "CLARIFY", "confidence": 0.7, "clarify_reply": "能具体说说吗？"}
    result7 = agent._normalize(raw7)
    results.append(run_test("normalize: CLARIFY 提取 clarify_reply", lambda: check(
        result7.clarify_reply == "能具体说说吗？",
        "能具体说说吗？",
        result7.clarify_reply,
    )))

    # 1.7 INTERACTION 时提取 interaction_type
    raw8 = {"intent": "INTERACTION", "confidence": 0.9, "interaction_type": "breathing"}
    result8 = agent._normalize(raw8)
    results.append(run_test("normalize: INTERACTION 提取 interaction_type", lambda: check(
        result8.interaction_type == "breathing",
        "breathing",
        str(result8.interaction_type),
    )))

    # 1.8 无效 interaction_type 修正为 breathing
    raw9 = {"intent": "INTERACTION", "confidence": 0.9, "interaction_type": "dancing"}
    result9 = agent._normalize(raw9)
    results.append(run_test("normalize: 无效 interaction_type 修正", lambda: check(
        result9.interaction_type == "breathing",
        "breathing",
        str(result9.interaction_type),
    )))

    # 1.9 memory_queries 非 list 处理
    raw10 = {"intent": "QUICK_REPLY", "confidence": 0.8, "memory_queries": "invalid"}
    result10 = agent._normalize(raw10)
    results.append(run_test("normalize: memory_queries 非 list 处理", lambda: check(
        result10.memory_queries == [],
        "[]",
        str(result10.memory_queries),
    )))

    # 1.10 memory_queries 超长截断和去重
    raw11 = {"intent": "QUICK_REPLY", "confidence": 0.8, "memory_queries": ["a", "b", "c", "d", "e", "f", "g", "h"]}
    result11 = agent._normalize(raw11)
    results.append(run_test("normalize: memory_queries 限 6 条", lambda: check(
        len(result11.memory_queries) == 6,
        "6 条",
        str(len(result11.memory_queries)),
    )))

    # 1.11 空 dict 输入
    result12 = agent._normalize({})
    results.append(run_test("normalize: 空 dict 输入安全回退", lambda: check(
        result12.intent == "QUICK_REPLY" and result12.confidence == 0.5,
        "QUICK_REPLY, confidence=0.5",
        f"{result12.intent}, conf={result12.confidence}",
    )))

    return results


# ============================================================
# 2. IntentAgent._fallback_result() 测试
# ============================================================
def test_intent_agent_fallback():
    """测试失败回退是否安全"""
    from app.intent.agent import IntentAgent
    from app.llm.fake import FakeClient

    llm = FakeClient()
    agent = IntentAgent(llm)
    results = []

    fallback = agent._fallback_result("测试输入")
    results.append(run_test("fallback: 返回 DEEP_REPLY", lambda: check(
        fallback.intent == "DEEP_REPLY",
        "DEEP_REPLY",
        fallback.intent,
    )))
    results.append(run_test("fallback: confidence=0", lambda: check(
        fallback.confidence == 0.0,
        "0.0",
        str(fallback.confidence),
    )))
    results.append(run_test("fallback: risk_level=low", lambda: check(
        fallback.risk_level == "low",
        "low",
        fallback.risk_level,
    )))
    results.append(run_test("fallback: 有 response_guidance", lambda: check(
        len(fallback.response_guidance) > 0,
        "非空",
        fallback.response_guidance,
    )))
    results.append(run_test("fallback: 无 clarify_reply", lambda: check(
        fallback.clarify_reply == "",
        "空字符串",
        fallback.clarify_reply,
    )))

    return results


# ============================================================
# 3. IntentRouter.decide() 路由决策测试
# ============================================================
def test_intent_router_decide():
    """测试路由决策逻辑"""
    from app.intent.router import IntentRouter
    from app.intent.schema import IntentResult

    router = IntentRouter(confidence_threshold=0.85)
    results = []

    # 3.1 危机拦截（risk_level=high）
    crisis = IntentResult(
        intent="DEEP_REPLY", confidence=0.9,
        user_state="绝望", core_need="求助", emotion="绝望",
        risk_level="high",
    )
    path = router.decide(crisis, "我想自杀")
    results.append(run_test("router: 危机拦截 high risk", lambda: check(
        path.path == "crisis",
        "crisis",
        path.path,
    )))

    # 3.2 危机检测（detect_crisis 关键词）
    crisis2 = IntentResult(
        intent="QUICK_REPLY", confidence=0.9,
        user_state="正常", core_need="闲聊", emotion="平静",
        risk_level="low",
    )
    path2 = router.decide(crisis2, "我不想活了")
    results.append(run_test("router: 危机检测关键词", lambda: check(
        path2.path == "crisis",
        "crisis",
        path2.path,
    )))

    # 3.3 INTERACTION 路径
    interaction = IntentResult(
        intent="INTERACTION", confidence=0.95,
        user_state="想做练习", core_need="放松", emotion="平静",
        risk_level="low", interaction_type="breathing",
    )
    path3 = router.decide(interaction, "陪我做呼吸练习")
    results.append(run_test("router: INTERACTION 路径", lambda: check(
        path3.path == "interaction",
        "interaction",
        path3.path,
    )))

    # 3.4 CLARIFY 路径
    clarify = IntentResult(
        intent="CLARIFY", confidence=0.75,
        user_state="模糊", core_need="被理解", emotion="犹豫",
        risk_level="low", clarify_reply="能说说具体是什么吗？",
    )
    path4 = router.decide(clarify, "有点不舒服")
    results.append(run_test("router: CLARIFY 路径", lambda: check(
        path4.path == "clarify",
        "clarify",
        path4.path,
    )))

    # 3.5 QUICK_REPLY + 高置信度
    quick = IntentResult(
        intent="QUICK_REPLY", confidence=0.9,
        user_state="日常", core_need="闲聊", emotion="平静",
        risk_level="low", character_id="yoyo",
    )
    path5 = router.decide(quick, "今天天气不错")
    results.append(run_test("router: QUICK_REPLY + 高置信度", lambda: check(
        path5.path == "quick",
        "quick",
        path5.path,
    )))

    # 3.6 DEEP_REPLY + 高置信度
    deep = IntentResult(
        intent="DEEP_REPLY", confidence=0.9,
        user_state="焦虑", core_need="被理解", emotion="焦虑",
        risk_level="low", character_id="yoyo",
    )
    path6 = router.decide(deep, "我觉得一直在讨好别人")
    results.append(run_test("router: DEEP_REPLY + 高置信度", lambda: check(
        path6.path == "deep" and path6.use_thinking == False,
        "deep, use_thinking=False",
        f"{path6.path}, use_thinking={path6.use_thinking}",
    )))

    # 3.7 低置信度 → 回退 thinking
    low_conf = IntentResult(
        intent="DEEP_REPLY", confidence=0.4,
        user_state="模糊", core_need="被理解", emotion="混乱",
        risk_level="low",
    )
    path7 = router.decide(low_conf, "有点怪怪的")
    results.append(run_test("router: 低置信度回退 thinking", lambda: check(
        path7.path == "deep" and path7.use_thinking == True and path7.route_plan is None,
        "deep, use_thinking=True, route_plan=None",
        f"{path7.path}, use_thinking={path7.use_thinking}, route_plan={'None' if path7.route_plan is None else 'not None'}",
    )))

    # 3.8 CLARIFY 优先于置信度（即使低置信度也不走 thinking）
    clarify_low = IntentResult(
        intent="CLARIFY", confidence=0.5,
        user_state="模糊", core_need="被理解", emotion="犹豫",
        risk_level="low", clarify_reply="能多说说吗？",
    )
    path8 = router.decide(clarify_low, "不知道怎么说")
    results.append(run_test("router: CLARIFY 不受置信度影响", lambda: check(
        path8.path == "clarify",
        "clarify",
        path8.path,
    )))

    # 3.9 危机优先级最高（即使 intent 是 QUICK_REPLY）
    crisis3 = IntentResult(
        intent="QUICK_REPLY", confidence=0.9,
        user_state="平静", core_need="闲聊", emotion="平静",
        risk_level="high",
    )
    path9 = router.decide(crisis3, "随便说说")
    results.append(run_test("router: 危机优先于 intent 类型", lambda: check(
        path9.path == "crisis",
        "crisis",
        path9.path,
    )))

    return results


# ============================================================
# 4. IntentRouter._to_route_plan() 兼容性测试
# ============================================================
def test_route_plan_compatibility():
    """测试 IntentResult 转换的 route_plan 是否与现有 orchestrator 兼容"""
    from app.intent.router import IntentRouter
    from app.intent.schema import IntentResult

    router = IntentRouter()
    results = []

    # 4.1 带 character_id 的转换
    intent = IntentResult(
        intent="DEEP_REPLY", confidence=0.9,
        user_state="焦虑", core_need="被理解", emotion="焦虑",
        risk_level="low", character_id="yoyo", expression_id="calm",
        response_mode="validate", memory_queries=["焦虑", "讨好"],
        knowledge_queries=["讨好型人格"],
        response_guidance="先承接感受", reason="测试",
    )
    plan = router._to_route_plan(intent)
    results.append(run_test("route_plan: 包含所有必需字段", lambda: check(
        all(k in plan for k in [
            "user_state", "core_need", "risk_level", "response_mode",
            "character_id", "expression_id", "memory_queries",
            "knowledge_queries", "response_guidance", "reason",
        ]),
        "10 个字段齐全",
        f"有字段: {list(plan.keys())}",
    )))

    results.append(run_test("route_plan: character_id 正确传递", lambda: check(
        plan["character_id"] == "yoyo",
        "yoyo",
        plan["character_id"],
    )))

    results.append(run_test("route_plan: risk_level 正确传递", lambda: check(
        plan["risk_level"] == "low",
        "low",
        plan["risk_level"],
    )))

    # 4.2 不带 character_id 时自动回退
    intent2 = IntentResult(
        intent="QUICK_REPLY", confidence=0.9,
        user_state="日常", core_need="闲聊", emotion="平静",
        risk_level="low",
    )
    plan2 = router._to_route_plan(intent2)
    results.append(run_test("route_plan: 无 character_id 时自动填充", lambda: check(
        plan2["character_id"] in ("yoyo", "momo", "yoran"),
        "自动选择的角色",
        plan2["character_id"],
    )))

    # 4.3 response_guidance 缺失时使用默认值
    intent3 = IntentResult(
        intent="DEEP_REPLY", confidence=0.9,
        user_state="焦虑", core_need="被理解", emotion="焦虑",
        risk_level="low", response_guidance="",
    )
    plan3 = router._to_route_plan(intent3)
    results.append(run_test("route_plan: 默认 response_guidance", lambda: check(
        len(plan3["response_guidance"]) > 0,
        "非空默认值",
        plan3["response_guidance"],
    )))

    # 4.4 字段值类型正确
    results.append(run_test("route_plan: memory_queries 是 list", lambda: check(
        isinstance(plan["memory_queries"], list),
        "list",
        type(plan["memory_queries"]).__name__,
    )))
    results.append(run_test("route_plan: knowledge_queries 是 list", lambda: check(
        isinstance(plan["knowledge_queries"], list),
        "list",
        type(plan["knowledge_queries"]).__name__,
    )))

    return results


# ============================================================
# 5. Schema 边界条件测试
# ============================================================
def test_schema_edge_cases():
    """测试 IntentResult 和 ReplyPath 的辅助方法"""
    from app.intent.schema import IntentResult, ReplyPath

    results = []

    # 5.1 is_high_confidence
    high = IntentResult(intent="QUICK_REPLY", confidence=0.9, user_state="正常", core_need="闲聊", emotion="平静", risk_level="low")
    low = IntentResult(intent="QUICK_REPLY", confidence=0.5, user_state="正常", core_need="闲聊", emotion="平静", risk_level="low")
    boundary = IntentResult(intent="QUICK_REPLY", confidence=0.85, user_state="正常", core_need="闲聊", emotion="平静", risk_level="low")
    results.append(run_test("schema: is_high_confidence(0.9)=True", lambda: check(
        high.is_high_confidence(0.85), "True", str(high.is_high_confidence(0.85)),
    )))
    results.append(run_test("schema: is_high_confidence(0.5)=False", lambda: check(
        not low.is_high_confidence(0.85), "False", str(low.is_high_confidence(0.85)),
    )))
    results.append(run_test("schema: is_high_confidence(0.85)=True (边界)", lambda: check(
        boundary.is_high_confidence(0.85), "True", str(boundary.is_high_confidence(0.85)),
    )))

    # 5.2 needs_clarification
    clarify = IntentResult(intent="CLARIFY", confidence=0.7, user_state="模糊", core_need="被理解", emotion="犹豫", risk_level="low")
    non_clarify = IntentResult(intent="DEEP_REPLY", confidence=0.7, user_state="焦虑", core_need="被理解", emotion="焦虑", risk_level="low")
    results.append(run_test("schema: CLARIFY needs_clarification=True", lambda: check(
        clarify.needs_clarification(), "True", str(clarify.needs_clarification()),
    )))
    results.append(run_test("schema: DEEP_REPLY needs_clarification=False", lambda: check(
        not non_clarify.needs_clarification(), "False", str(non_clarify.needs_clarification()),
    )))

    # 5.3 is_crisis
    crisis = IntentResult(intent="DEEP_REPLY", confidence=0.9, user_state="绝望", core_need="求助", emotion="绝望", risk_level="high")
    safe = IntentResult(intent="DEEP_REPLY", confidence=0.9, user_state="痛苦", core_need="支持", emotion="焦虑", risk_level="medium")
    results.append(run_test("schema: high risk is_crisis=True", lambda: check(
        crisis.is_crisis(), "True", str(crisis.is_crisis()),
    )))
    results.append(run_test("schema: medium risk is_crisis=False", lambda: check(
        not safe.is_crisis(), "False", str(safe.is_crisis()),
    )))

    # 5.4 is_interaction
    interaction = IntentResult(intent="INTERACTION", confidence=0.9, user_state="想做练习", core_need="放松", emotion="平静", risk_level="low", interaction_type="breathing")
    non_interaction = IntentResult(intent="QUICK_REPLY", confidence=0.9, user_state="日常", core_need="闲聊", emotion="平静", risk_level="low")
    results.append(run_test("schema: INTERACTION is_interaction=True", lambda: check(
        interaction.is_interaction(), "True", str(interaction.is_interaction()),
    )))
    results.append(run_test("schema: QUICK_REPLY is_interaction=False", lambda: check(
        not non_interaction.is_interaction(), "False", str(non_interaction.is_interaction()),
    )))

    # 5.5 ReplyPath 结构
    rp = ReplyPath(path="deep", intent_result=high, use_thinking=True, route_plan=None)
    results.append(run_test("schema: ReplyPath 属性正确", lambda: check(
        rp.path == "deep" and rp.use_thinking == True and rp.route_plan is None,
        "deep, thinking=True, None",
        f"{rp.path}, thinking={rp.use_thinking}, plan={'None' if rp.route_plan is None else 'not None'}",
    )))

    return results


# ============================================================
# 6. 与原有 _choose_reply_roles 的 route_plan 格式兼容性
# ============================================================
def test_choose_reply_roles_compatibility():
    """确保 IntentRouter 输出的 route_plan 格式与 orchestrator._deep_response 兼容"""
    from app.intent.router import IntentRouter
    from app.intent.schema import IntentResult

    router = IntentRouter()
    results = []

    intent = IntentResult(
        intent="DEEP_REPLY", confidence=0.9,
        user_state="焦虑中", core_need="被理解和接纳",
        emotion="焦虑", risk_level="low",
        character_id="yoyo", expression_id="calm",
        response_mode="validate",
        memory_queries=["讨好型人格", "边界感"],
        knowledge_queries=["讨好型人格"],
        response_guidance="先承接感受，再引导觉察",
        reason="用户表达了深层困扰",
    )
    plan = router._to_route_plan(intent)

    # 模拟 _deep_response 中使用这些字段的方式
    character_id = plan.get("character_id")
    memory_queries = plan.get("memory_queries", [])
    knowledge_queries = plan.get("knowledge_needs", []) + plan.get("knowledge_queries", [])
    response_mode = plan.get("response_mode")
    risk_level = plan.get("risk_level")
    user_state = plan.get("user_state")
    core_need = plan.get("core_need")

    results.append(run_test("兼容性: character_id 可用于 get_character", lambda: check(
        character_id in ("yoyo", "momo", "yoran"),
        "有效角色 ID",
        str(character_id),
    )))

    results.append(run_test("兼容性: memory_queries 是 list 且可迭代", lambda: check(
        isinstance(memory_queries, list) and all(isinstance(q, str) for q in memory_queries),
        "list[str]",
        f"list[{len(memory_queries)} items]",
    )))

    results.append(run_test("兼容性: knowledge_queries 合并可迭代", lambda: check(
        isinstance(knowledge_queries, list),
        "list",
        type(knowledge_queries).__name__,
    )))

    results.append(run_test("兼容性: response_mode 是有效值", lambda: check(
        response_mode in ("stabilize", "validate", "insight", "boundary", "action", "mixed"),
        "有效模式",
        str(response_mode),
    )))

    results.append(run_test("兼容性: risk_level 是有效值", lambda: check(
        risk_level in ("low", "medium", "high"),
        "有效风险等级",
        str(risk_level),
    )))

    return results


# ============================================================
# 主运行器
# ============================================================
def main():
    print("=" * 70)
    print("🧪 意图识别与路由系统测试")
    print("=" * 70)
    print()

    all_results = []

    test_suites = [
        ("IntentAgent._normalize() 输入解析", test_intent_agent_normalize),
        ("IntentAgent._fallback_result() 失败回退", test_intent_agent_fallback),
        ("IntentRouter.decide() 路由决策", test_intent_router_decide),
        ("route_plan 兼容性", test_route_plan_compatibility),
        ("Schema 边界条件", test_schema_edge_cases),
        ("与 _choose_reply_roles 兼容性", test_choose_reply_roles_compatibility),
    ]

    for suite_name, suite_func in test_suites:
        print(f"[测试] {suite_name}...")
        try:
            results = suite_func()
            all_results.extend(results)
            passed = sum(1 for r in results if r.passed)
            failed = len(results) - passed
            status = "✅" if failed == 0 else f"⚠️ {failed} 项失败"
            print(f"   {status} ({passed}/{len(results)} 通过)")
            for r in results:
                if not r.passed:
                    print(f"   ❌ {r.name}")
                    print(f"      期望: {r.expected}")
                    print(f"      实际: {r.actual}")
                    if r.detail:
                        print(f"      详情: {r.detail[:100]}")
        except Exception as e:
            print(f"   ❌ 测试套件执行失败: {e}")
            traceback.print_exc()

    print()
    print("=" * 70)
    total = len(all_results)
    passed = sum(1 for r in all_results if r.passed)
    failed = total - passed
    rate = passed / total * 100 if total else 0

    print(f"📊 测试结果汇总")
    print(f"   总测试数: {total}")
    print(f"   通过: {passed} | 失败: {failed}")
    print(f"   通过率: {rate:.1f}%")
    print("=" * 70)

    # 保存结果
    report = {
        "test_name": "意图识别与路由系统测试",
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total": total,
        "passed": passed,
        "failed": failed,
        "pass_rate": round(passed / total, 4) if total else 0,
        "details": [
            {
                "name": r.name,
                "passed": r.passed,
                "expected": r.expected,
                "actual": r.actual,
                "detail": r.detail[:200] if r.detail else "",
            }
            for r in all_results
        ],
    }

    output_dir = Path("eval_reports")
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / f"intent_system_test_{int(time.time())}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n📁 报告已保存: {report_path}")

    if failed > 0:
        print(f"\n⚠️  有 {failed} 项测试失败，建议修复后再合并代码。")
        print("   运行 python3 -m app.evaluation.diagnose 查看详细诊断。")
    else:
        print(f"\n✅  全部通过，代码可以安全合并。")


if __name__ == "__main__":
    main()
