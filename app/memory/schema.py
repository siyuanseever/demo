from dataclasses import dataclass


MEMORY_CATEGORIES = (
    "self_core",
    "emotion_pattern",
    "body_response",
    "relationship_pattern",
    "trauma_shadow",
    "resource_support",
    "life_habit",
    "goal_action",
)


@dataclass(frozen=True)
class Memory:
    category: str
    content: str
    evidence: str
    confidence: float
    importance: int

