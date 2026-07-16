"""
意图识别与现有 Orchestrator 的集成示例。

展示了如何在 reply_detail 流程中嵌入 IntentAgent 和 IntentRouter，
实现双路径（快速回复 + 深度回复）。

使用方法：
    将此逻辑合并到 ConversationOrchestrator.reply_detail 中。
"""

import logging
import time
from concurrent.futures import ThreadPoolExecutor

from app.agents.safety import CRISIS_RESPONSE, detect_crisis
from app.characters import get_character, normalize_expression_id
from app.intent.agent import IntentAgent
from app.intent.router import IntentRouter
from app.intent.schema import ReplyPath

logger = logging.getLogger(__name__)


def reply_with_intent(
    self,
    session_id: str,
    user_text: str,
    character_id: str | None = None,
) -> dict:
    """
    嵌入意图识别的回复流程。

    与原有 reply_detail 的差异：
    1. 用户输入后，先并行启动：意图识别 + 快速回复生成
    2. 意图识别完成后，决定是返回快速回复还是继续深度回复
    3. 如果深度回复，复用原有的记忆检索、知识检索、角色选择逻辑
    """
    started_at = time.monotonic()
    debug_trace = {
        "mode": "intent_routing",
        "steps": [],
        "llm_calls": [],
    }

    # ===== 阶段 1：并行启动意图识别 + 快速回复 =====
    intent_agent = IntentAgent(self.llm, confidence_threshold=0.85)
    router = IntentRouter(confidence_threshold=0.85)

    messages = self.store.get_session_messages(session_id)
    recent_history = [{"role": m["role"], "content": m["content"]} for m in messages[-10:]]

    with ThreadPoolExecutor(max_workers=2, thread_name_prefix="intent") as executor:
        intent_future = executor.submit(intent_agent.recognize, user_text, recent_history)

        # 快速回复也先启动（基于轻量上下文）
        quick_reply_future = executor.submit(
            self._generate_quick_reply,
            user_text,
            recent_history,
            character_id,
        )

        intent_result = intent_future.result()
        quick_reply_text = quick_reply_future.result()

    debug_trace["steps"].append({
        "name": "intent_recognition",
        "status": "done",
        "output": {
            "intent": intent_result.intent,
            "confidence": intent_result.confidence,
            "risk_level": intent_result.risk_level,
            "emotion": intent_result.emotion,
        },
    })

    # ===== 阶段 2：路由决策 =====
    reply_path = router.decide(intent_result, user_text)

    if reply_path.path == "crisis":
        # 危机路径：直接返回危机回复
        character = get_character(character_id) if character_id else get_character("yoyo")
        expression_id = normalize_expression_id(character.id, "concerned")
        self.store.add_message(
            session_id,
            "assistant",
            CRISIS_RESPONSE,
            model="safety",
            metadata={"character_id": character.id, "expression_id": expression_id},
        )
        return {
            "reply": CRISIS_RESPONSE,
            "knowledge_cards": [],
            "character": character.to_public_dict(),
            "expression": {"id": expression_id, **(character.expressions or {}).get(expression_id, {})},
            "route_plan": None,
            "debug_trace": debug_trace,
        }

    if reply_path.path == "quick":
        # 快速路径：直接返回轻量回复
        assert reply_path.route_plan is not None
        character = get_character(reply_path.route_plan["character_id"])
        expression_id = reply_path.route_plan["expression_id"]
        self.store.add_message(
            session_id,
            "assistant",
            quick_reply_text,
            model="quick",
            metadata={
                "character_id": character.id,
                "expression_id": expression_id,
                "route_plan": reply_path.route_plan,
            },
        )
        debug_trace["steps"].append({
            "name": "quick_reply",
            "status": "done",
            "summary": "意图识别判断为轻量闲聊，直接返回快速回复。",
        })
        return {
            "reply": quick_reply_text,
            "knowledge_cards": [],
            "character": character.to_public_dict(),
            "expression": {"id": expression_id, **(character.expressions or {}).get(expression_id, {})},
            "route_plan": reply_path.route_plan,
            "debug_trace": debug_trace,
        }

    if reply_path.path == "clarify":
        # 追问路径：快速回复 + 追问
        clarify_text = quick_reply_text + "\n\n（我想更理解你，可以多告诉我一点吗？）"
        assert reply_path.route_plan is not None
        character = get_character(reply_path.route_plan["character_id"])
        expression_id = reply_path.route_plan["expression_id"]
        self.store.add_message(
            session_id,
            "assistant",
            clarify_text,
            model="clarify",
            metadata={
                "character_id": character.id,
                "expression_id": expression_id,
                "route_plan": reply_path.route_plan,
            },
        )
        return {
            "reply": clarify_text,
            "knowledge_cards": [],
            "character": character.to_public_dict(),
            "expression": {"id": expression_id, **(character.expressions or {}).get(expression_id, {})},
            "route_plan": reply_path.route_plan,
            "debug_trace": debug_trace,
        }

    # ===== 阶段 3：深度回复路径 =====
    # 如果 confidence 低，使用 thinking 模式重新做策略规划
    if reply_path.use_thinking:
        route_plan = self._choose_reply_roles(
            session_id,
            user_text,
            debug_trace=debug_trace,
        )
    else:
        route_plan = reply_path.route_plan

    # 复用原有的深度回复逻辑
    return self._generate_deep_reply(
        session_id,
        user_text,
        route_plan,
        debug_trace,
        started_at,
    )


def _generate_quick_reply(
    self,
    user_text: str,
    history: list[dict],
    character_id: str | None,
) -> str:
    """
    生成快速回复。使用轻量模型、短上下文。
    此为占位实现，实际可接入轻量模型或模板回复。
    """
    # TODO: 接入轻量模型（如 deepseek-v4-flash 的更快配置）
    # 当前简化为基于规则的快速响应
    if "谢谢" in user_text or "感谢" in user_text:
        return "不用谢，能陪着你就很好。"
    if "早上好" in user_text or "晚上好" in user_text:
        return "你好呀，今天过得怎么样？"
    if "好累" in user_text and len(user_text) < 20:
        return "累了就先歇一歇，不用急着说什么。"
    return "我在听，你想说说吗？"
