import logging

from app.agents.safety import CRISIS_RESPONSE, detect_crisis
from app.characters import auto_select_character, get_character, normalize_expression_id
from app.intent.schema import IntentResult, ReplyPath


class IntentRouter:
    """
    意图路由决策层。

    职责：
    1. 根据 IntentAgent 的输出决定走哪条回复路径
    2. 处理置信度阈值判断、危机拦截、交互路由
    3. 将 IntentResult 转换为与现有系统兼容的 route_plan

    路径说明：
    - crisis:      危机干预，直接返回危机回复
    - interaction: 交互引导（呼吸练习等），模板化
    - clarify:     追问路径，使用 intent 阶段已生成的追问文本
    - quick:       轻量模型快速回复
    - deep:        完整深度回复（高置信度用 intent route_plan，低置信度回退 thinking）
    """

    def __init__(
        self,
        confidence_threshold: float = 0.85,
        re_router_threshold: float = 0.6,
    ) -> None:
        self.confidence_threshold = confidence_threshold
        self.re_router_threshold = re_router_threshold
        self.logger = logging.getLogger(__name__)

    def decide(self, intent_result: IntentResult, user_text: str) -> ReplyPath:
        """
        根据意图识别结果做出路由决策。

        Args:
            intent_result: IntentAgent 的输出
            user_text: 用户原始输入（用于危机检测）

        Returns:
            ReplyPath: 包含目标路径、是否需要深度思考、route_plan
        """
        # 第一层：危机拦截（最高优先级）
        if intent_result.is_crisis() or detect_crisis(user_text):
            self.logger.warning("crisis detected risk=%s", intent_result.risk_level)
            return ReplyPath(
                path="crisis",
                intent_result=intent_result,
                use_thinking=False,
                route_plan=None,
            )

        # 第二层：交互路径
        if intent_result.is_interaction():
            return ReplyPath(
                path="interaction",
                intent_result=intent_result,
                use_thinking=False,
                route_plan=self._to_route_plan(intent_result),
            )

        # 第三层：追问路径
        if intent_result.needs_clarification():
            return ReplyPath(
                path="clarify",
                intent_result=intent_result,
                use_thinking=False,
                route_plan=self._to_route_plan(intent_result),
            )

        # 第四层：高置信度快速路由
        if intent_result.is_high_confidence(self.confidence_threshold):
            if intent_result.intent == "QUICK_REPLY":
                return ReplyPath(
                    path="quick",
                    intent_result=intent_result,
                    use_thinking=False,
                    route_plan=self._to_route_plan(intent_result),
                )
            else:
                return ReplyPath(
                    path="deep",
                    intent_result=intent_result,
                    use_thinking=False,
                    route_plan=self._to_route_plan(intent_result),
                )

        # 第五层：低置信度 → 启用深度思考重新判断
        self.logger.info(
            "low confidence=%.2f < %.2f, fallback to thinking mode",
            intent_result.confidence,
            self.confidence_threshold,
        )
        return ReplyPath(
            path="deep",
            intent_result=intent_result,
            use_thinking=True,
            route_plan=None,
        )

    def check_reroute(self, reply_path: ReplyPath, deep_model_analysis: str) -> ReplyPath | None:
        """
        下游模型在执行过程中发现意图不匹配时，触发重新路由。

        Args:
            reply_path: 当前的路由决策
            deep_model_analysis: 深度模型对意图的分析文本
                应包含特定标记如 [[INTENT_MISMATCH:DEEP_REPLY]]

        Returns:
            新的 ReplyPath（如果需要重新路由），否则 None
        """
        import re

        mismatch = re.search(r"\[\[INTENT_MISMATCH:(\w+)\]\]", deep_model_analysis)
        if not mismatch:
            return None

        corrected_intent = mismatch.group(1).upper()
        if corrected_intent not in {"QUICK_REPLY", "DEEP_REPLY", "CLARIFY"}:
            return None

        self.logger.info(
            "re-routing from %s to %s",
            reply_path.intent_result.intent,
            corrected_intent,
        )

        corrected = IntentResult(
            intent=corrected_intent,
            confidence=reply_path.intent_result.confidence,
            user_state=reply_path.intent_result.user_state,
            core_need=reply_path.intent_result.core_need,
            emotion=reply_path.intent_result.emotion,
            risk_level=reply_path.intent_result.risk_level,
            memory_queries=reply_path.intent_result.memory_queries,
            knowledge_queries=reply_path.intent_result.knowledge_queries,
            character_id=reply_path.intent_result.character_id,
            expression_id=reply_path.intent_result.expression_id,
            response_mode=reply_path.intent_result.response_mode,
            response_guidance=reply_path.intent_result.response_guidance,
            reason=f"重新路由: {reply_path.intent_result.intent} -> {corrected_intent}",
            clarify_reply=reply_path.intent_result.clarify_reply,
            interaction_type=reply_path.intent_result.interaction_type,
        )
        return self.decide(corrected, "")

    def _to_route_plan(self, intent: IntentResult) -> dict:
        """
        将 IntentResult 转换为与现有 orchestrator 兼容的 route_plan 字典。
        """
        character_id = intent.character_id
        if not character_id:
            character = auto_select_character("")
            character_id = character.id

        expression_id = normalize_expression_id(character_id, intent.expression_id)

        return {
            "user_state": intent.user_state,
            "core_need": intent.core_need,
            "risk_level": intent.risk_level,
            "response_mode": intent.response_mode,
            "character_id": character_id,
            "expression_id": expression_id,
            "knowledge_needs": [],
            "memory_queries": intent.memory_queries,
            "knowledge_queries": intent.knowledge_queries,
            "response_guidance": intent.response_guidance or "先承接，再给出克制的心理学解释；避免替用户下过重结论。",
            "reason": intent.reason or "基于统一意图识别agent的快速判断。",
        }
