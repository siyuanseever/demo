from dataclasses import dataclass, field
from typing import Literal

IntentType = Literal["QUICK_REPLY", "DEEP_REPLY", "CLARIFY", "INTERACTION"]
RiskLevel = Literal["low", "medium", "high"]
InteractionType = Literal["breathing", "body_scan", "mood_check", "mini_game"]


@dataclass(frozen=True)
class IntentResult:
    """意图识别结果，由 IntentAgent 输出。"""

    intent: IntentType
    confidence: float
    user_state: str
    core_need: str
    emotion: str
    risk_level: RiskLevel
    memory_queries: list[str] = field(default_factory=list)
    knowledge_queries: list[str] = field(default_factory=list)
    character_id: str = ""
    expression_id: str = ""
    response_mode: str = "mixed"
    response_guidance: str = ""
    reason: str = ""
    clarify_reply: str = ""
    interaction_type: InteractionType | None = None

    def is_high_confidence(self, threshold: float = 0.85) -> bool:
        return self.confidence >= threshold

    def needs_clarification(self) -> bool:
        return self.intent == "CLARIFY"

    def is_crisis(self) -> bool:
        return self.risk_level == "high"

    def is_interaction(self) -> bool:
        return self.intent == "INTERACTION"


@dataclass(frozen=True)
class ReplyPath:
    """路由决策结果，由 IntentRouter 输出。"""

    path: Literal["quick", "deep", "clarify", "crisis", "interaction"]
    intent_result: IntentResult
    use_thinking: bool = False
    route_plan: dict | None = None
