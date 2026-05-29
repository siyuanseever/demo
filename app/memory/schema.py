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


MEMORY_SUBCATEGORIES = {
    "self_core": (
        "identity",
        "values",
        "energy_source",
        "boundary",
        "self_image",
    ),
    "emotion_pattern": (
        "anxiety",
        "freeze_response",
        "shame",
        "grief",
        "anger",
    ),
    "body_response": (
        "fatigue",
        "tension",
        "sleep",
        "somatic_signal",
        "collapse",
    ),
    "relationship_pattern": (
        "family",
        "intimacy",
        "work_relation",
        "attachment_trigger",
        "support_need",
    ),
    "trauma_shadow": (
        "fear",
        "abandonment",
        "humiliation",
        "suppression",
        "dark_part",
    ),
    "resource_support": (
        "person",
        "place",
        "activity",
        "ritual",
        "inner_strength",
    ),
    "life_habit": (
        "routine",
        "food",
        "movement",
        "work_rhythm",
        "rest",
    ),
    "goal_action": (
        "career",
        "project",
        "small_step",
        "avoidance",
        "decision",
    ),
}


MEMORY_STATUSES = ("active", "merged", "contradicted", "archived")


@dataclass(frozen=True)
class Memory:
    category: str
    content: str
    evidence: str
    confidence: float
    importance: int
