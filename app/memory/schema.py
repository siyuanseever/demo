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
    exact_alias = aliases.get(category, {}).get(normalized)
    if exact_alias:
        return exact_alias

    pattern_aliases = {
        "self_core": (
            (("critic", "judgment", "productivity", "stagnation"), "inner_critic"),
            (("self_worth", "self_image", "self_loathing", "ideal_self"), "self_image"),
            (("self_care", "self_kindness", "compassion"), "self_compassion"),
            (("autonomy", "boundary"), "boundary"),
            (("energy", "motivation", "creative_expression"), "energy_source"),
            (("value", "philosophy", "belief", "meaning", "existential"), "values"),
            (("identity", "authentic", "belonging", "lost_self", "life_narrative"), "identity"),
        ),
        "emotion_pattern": (
            (("freeze", "paralysis", "inertia", "withdrawal", "avoidance"), "freeze_response"),
            (("shame", "self_blame", "self_criticism", "guilt", "inferiority"), "shame"),
            (("anger", "disgust", "frustration", "resistance"), "anger"),
            (("loneliness", "isolation", "disconnection"), "loneliness"),
            (("numb", "dissociat", "meaninglessness"), "numbness"),
            (("grief", "sadness", "loss", "longing", "despair", "hopeless", "depress", "core_pain"), "grief"),
            (("anxiety", "fear", "pressure", "overwhelm", "hypervigilance", "rumination"), "anxiety"),
        ),
        "body_response": (
            (("sleep", "insomnia"), "sleep"),
            (("freeze", "collapse", "shutdown"), "collapse"),
            (("sensory", "eye_strain"), "sensory_overload"),
            (("pain", "headache", "discomfort"), "pain"),
            (("tension", "hyperarousal", "chest"), "tension"),
            (("fatigue", "dizziness", "illness_fragility"), "fatigue"),
            (("sensation", "touch", "warming"), "somatic_signal"),
        ),
        "relationship_pattern": (
            (("mother", "father", "parent", "family"), "family"),
            (("workplace", "authority", "leadership", "career"), "work_relation"),
            (("boundary", "control", "conflict", "injustice"), "boundary_conflict"),
            (("rejection", "cold_violence", "loss_and_disconnection"), "rejection"),
            (("attachment", "unrequited", "intimacy", "love"), "attachment_trigger"),
            (("support", "remembered", "social_isolation"), "support_need"),
        ),
        "trauma_shadow": (
            (("abandon", "rejection", "betrayal", "support_void"), "abandonment"),
            (("humiliat", "worthless", "imposter", "educational"), "humiliation"),
            (("suppress", "power_abuse", "exploitation"), "suppression"),
            (("hypervigilance",), "hypervigilance"),
            (("trigger", "repetition"), "trigger"),
            (("fear", "anxiety", "hopeless", "collapse"), "fear"),
            (("family", "developmental", "early_onset", "parental"), "dark_part"),
        ),
        "resource_support": (
            (("therap", "doctor", "professional"), "professional_support"),
            (("music", "reading", "creative", "cultural", "expression"), "creative_resource"),
            (("person", "teacher", "role_model", "social", "network", "family"), "person"),
            (("nature", "environment", "place"), "place"),
            (("ritual", "anchor", "memory", "transitional_object"), "ritual"),
            (("strength", "kindness", "love_for_others"), "inner_strength"),
            (("activity", "coping", "self_care", "small_step", "soothing"), "activity"),
        ),
        "life_habit": (
            (("sleep", "rest", "break"), "rest"),
            (("eye", "screen", "digital"), "digital_habit"),
            (("space", "environment", "home"), "environment"),
            (("food", "meal"), "food"),
            (("movement", "exercise"), "movement"),
            (("work",), "work_rhythm"),
            (("routine", "habit", "pattern", "care"), "routine"),
        ),
        "goal_action": (
            (("career", "job", "work"), "career"),
            (("uncertain", "unknown"), "uncertainty"),
            (("decision", "choice", "clarification"), "decision"),
            (("avoid",), "avoidance"),
            (("learn", "study"), "learning"),
            (("project",), "project"),
            (("action", "step", "plan", "habit", "intention"), "small_step"),
        ),
    }
    for patterns, target in pattern_aliases.get(category, ()):
        if any(pattern in normalized for pattern in patterns):
            return target
    return "general"


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
