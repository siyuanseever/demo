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
        "inner_critic",
        "self_compassion",
        "general",
    ),
    "emotion_pattern": (
        "anxiety",
        "freeze_response",
        "shame",
        "grief",
        "anger",
        "loneliness",
        "numbness",
        "general",
    ),
    "body_response": (
        "fatigue",
        "tension",
        "sleep",
        "somatic_signal",
        "collapse",
        "sensory_overload",
        "pain",
        "general",
    ),
    "relationship_pattern": (
        "family",
        "intimacy",
        "work_relation",
        "attachment_trigger",
        "support_need",
        "rejection",
        "boundary_conflict",
        "general",
    ),
    "trauma_shadow": (
        "fear",
        "abandonment",
        "humiliation",
        "suppression",
        "dark_part",
        "hypervigilance",
        "trigger",
        "general",
    ),
    "resource_support": (
        "person",
        "place",
        "activity",
        "ritual",
        "inner_strength",
        "professional_support",
        "creative_resource",
        "general",
    ),
    "life_habit": (
        "routine",
        "food",
        "movement",
        "work_rhythm",
        "rest",
        "environment",
        "digital_habit",
        "general",
    ),
    "goal_action": (
        "career",
        "project",
        "small_step",
        "avoidance",
        "decision",
        "uncertainty",
        "learning",
        "general",
    ),
}


MEMORY_STATUSES = ("active", "merged", "contradicted", "archived")


def normalize_memory_subcategory(category: str, subcategory: str | None) -> str:
    """Keep memory subcategories inside the fixed product taxonomy."""
    allowed = MEMORY_SUBCATEGORIES.get(category)
    if not allowed:
        return "general"
    normalized = str(subcategory or "").strip().lower().replace("-", "_").replace(" ", "_")
    if normalized in allowed:
        return normalized

    aliases = {
        "self_core": {
            "self_worth": "self_image",
            "self_esteem": "self_image",
            "self_criticism": "inner_critic",
            "inner_critic_pattern": "inner_critic",
            "self_care": "self_compassion",
            "core_value": "values",
            "personal_boundary": "boundary",
        },
        "emotion_pattern": {
            "fear": "anxiety",
            "sadness": "grief",
            "freeze": "freeze_response",
            "emotional_numbness": "numbness",
            "lonely": "loneliness",
        },
        "body_response": {
            "exhaustion": "fatigue",
            "body_tension": "tension",
            "insomnia": "sleep",
            "somatic": "somatic_signal",
            "shutdown": "collapse",
            "overload": "sensory_overload",
        },
        "relationship_pattern": {
            "attachment": "attachment_trigger",
            "rejection_sensitivity": "rejection",
            "workplace": "work_relation",
            "friendship": "support_need",
            "relationship_boundary": "boundary_conflict",
        },
        "trauma_shadow": {
            "trauma_trigger": "trigger",
            "threat_response": "trigger",
            "vigilance": "hypervigilance",
            "rejection": "abandonment",
        },
        "resource_support": {
            "therapy": "professional_support",
            "therapist": "professional_support",
            "music": "creative_resource",
            "game": "activity",
            "hobby": "activity",
        },
        "life_habit": {
            "schedule": "routine",
            "exercise": "movement",
            "sleep": "rest",
            "screen_time": "digital_habit",
            "home": "environment",
        },
        "goal_action": {
            "job": "career",
            "work": "career",
            "next_step": "small_step",
            "choice": "decision",
            "study": "learning",
            "unknown_future": "uncertainty",
        },
    }
    return aliases.get(category, {}).get(normalized, "general")


STATE_PROFILE_DOMAINS = (
    "self_relation",
    "emotion_regulation",
    "relationship",
    "agency_boundary",
    "trauma_pattern",
    "meaning_value",
)


STATE_PROFILE_TRENDS = (
    "unknown",
    "stable",
    "softening",
    "intensifying",
    "fluctuating",
    "integrating",
)


MENTAL_STATUS_MOODS = (
    "平静",
    "愉悦",
    "焦虑",
    "抑郁",
    "愤怒",
    "悲伤",
    "疲惫",
    "麻木",
    "恐惧",
    "羞耻",
    "兴奋",
    "不安",
    "孤独",
    "希望",
)


@dataclass(frozen=True)
class Memory:
    category: str
    content: str
    evidence: str
    confidence: float
    importance: int
