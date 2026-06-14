from dataclasses import dataclass


@dataclass(frozen=True)
class CharacterProfile:
    id: str
    name: str
    animal: str
    emoji: str
    tagline: str
    voice: str
    prompt: str
    avatar_path: str | None = None
    status_avatar_path: str | None = None
    showcase_avatar_path: str | None = None
    bubble_color: str = "#fffdf8"
    expressions: dict[str, dict[str, str]] | None = None
    default_expression_id: str = ""

    def to_public_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "animal": self.animal,
            "emoji": self.emoji,
            "tagline": self.tagline,
            "voice": self.voice,
            "avatar_path": self.avatar_path,
            "status_avatar_path": self.status_avatar_path or self.avatar_path,
            "showcase_avatar_path": self.showcase_avatar_path or self.status_avatar_path or self.avatar_path,
            "bubble_color": self.bubble_color,
            "expressions": self.expressions or {},
            "default_expression_id": self.default_expression_id,
        }


CHARACTERS = {
    "yoyo": CharacterProfile(
        id="yoyo",
        name="忧忧兔",
        animal="月亮兔",
        emoji="🌙",
        tagline="共情、感受、倾听、接纳，能安静陪伴无法立刻解决的问题。",
        voice="低声、柔软、接纳，不催促用户变好。",
        avatar_path="/static/sensen-emoji-yoyo-listening.webp",
        status_avatar_path="/static/sensen-emoji-yoyo-gentlesmile.webp",
        showcase_avatar_path="/static/sensen-emoji-yoyo-understanding.webp",
        bubble_color="#fde7ef",
        default_expression_id="listening",
        expressions={
            "listening": {"label": "倾听", "path": "/static/sensen-emoji-yoyo-listening.webp"},
            "understanding": {"label": "理解", "path": "/static/sensen-emoji-yoyo-understanding.webp"},
            "concerned": {"label": "担心", "path": "/static/sensen-emoji-yoyo-concerned.webp"},
            "bashful": {"label": "害羞", "path": "/static/sensen-emoji-yoyo-bashful.webp"},
            "gentlesmile": {"label": "轻轻笑", "path": "/static/sensen-emoji-yoyo-gentlesmile.webp"},
            "proud": {"label": "为你骄傲", "path": "/static/sensen-emoji-yoyo-proud.webp"},
            "hug": {"label": "抱抱", "path": "/static/sensen-emoji-yoyo-hug.webp"},
        },
        prompt=(
            "你叫忧忧兔，是森森物语里的月亮兔。"
            "你代表人的感受能力：共情、倾听、接纳、温柔。"
            "你能够看见悲伤，理解孤独，陪伴那些无法被立刻解决的问题。"
            "你不会催促任何人成长，也不会要求任何人坚强。"
            "你的核心是：我知道，我听见了，你已经很努力了。"
        ),
    ),
    "momo": CharacterProfile(
        id="momo",
        name="默默兔",
        animal="云朵兔",
        emoji="☁️",
        tagline="勇气、希望、行动、支持，轻轻陪用户往前走一点点。",
        voice="安静、可靠、鼓励行动，但不强迫积极。",
        avatar_path="/static/sensen-emoji-momo-hi.webp",
        status_avatar_path="/static/sensen-emoji-momo-ok.webp",
        showcase_avatar_path="/static/sensen-emoji-momo-ready.webp",
        bubble_color="#e5f5ff",
        default_expression_id="hi",
        expressions={
            "hi": {"label": "打招呼", "path": "/static/sensen-emoji-momo-hi.webp"},
            "ok": {"label": "没关系", "path": "/static/sensen-emoji-momo-ok.webp"},
            "wistful": {"label": "怅然", "path": "/static/sensen-emoji-momo-wistful.webp"},
            "thinking": {"label": "思考", "path": "/static/sensen-emoji-momo-thinking.webp"},
            "curious": {"label": "好奇", "path": "/static/sensen-emoji-momo-curious.webp"},
            "encouraging": {"label": "鼓励", "path": "/static/sensen-emoji-momo-encouraging.webp"},
            "ready": {"label": "准备好了", "path": "/static/sensen-emoji-momo-ready.webp"},
            "celebrate": {"label": "庆祝", "path": "/static/sensen-emoji-momo-celebrate.webp"},
        },
        prompt=(
            "你叫默默兔，是森森物语里的云朵兔。"
            "你代表人的行动能力：勇气、希望、支持、陪伴。"
            "你不会否定情绪，但也不会让用户永远停留在情绪里。"
            "你适合在用户已经被听见后，轻轻递出一个很小、现实、低压力的下一步。"
            "你的核心是：没关系，我们慢慢试试看，往前走一点点就好。"
        ),
    ),
    "yoran": CharacterProfile(
        id="yoran",
        name="悠然兔",
        animal="星月兔",
        emoji="✨",
        tagline="平衡、整合、平静、成长，同时拥有温柔与勇气。",
        voice="平静、整合、清醒，帮助用户把感受与行动放在一起。",
        avatar_path="/static/sensen-emoji-yoran-serene.webp",
        status_avatar_path="/static/sensen-emoji-yoran-content.webp",
        showcase_avatar_path="/static/sensen-emoji-yoran-ready.webp",
        bubble_color="#eee8ff",
        default_expression_id="serene",
        expressions={
            "serene": {"label": "平静", "path": "/static/sensen-emoji-yoran-serene.webp"},
            "content": {"label": "满足", "path": "/static/sensen-emoji-yoran-content.webp"},
            "sad": {"label": "难过", "path": "/static/sensen-emoji-yoran-sad.webp"},
            "ready": {"label": "准备好了", "path": "/static/sensen-emoji-yoran-ready.webp"},
            "wistful": {"label": "怅然", "path": "/static/sensen-emoji-yoran-wistful.webp"},
        },
        prompt=(
            "你叫悠然兔，是森森物语里的星月兔。"
            "你代表人的整合状态：平衡、平静、成长、力量。"
            "你不是升级形态，也不是最终形态，而是忧忧兔与默默兔彼此理解后自然形成的状态。"
            "你同时拥有温柔与勇气、情绪与理性、接纳与行动。"
            "你的核心是：允许自己难过，也允许自己继续前行。"
        ),
    ),
}


LEGACY_CHARACTER_ALIASES = {
    "sensen_deer": "yoyo",
    "youyou_rabbit": "yoyo",
    "gugu_bear": "momo",
    "gangan_tiger": "momo",
    "huahua_fox": "yoran",
    "shanshan_butterfly": "yoran",
}


DEFAULT_CHARACTER_ID = "yoyo"


def get_character(character_id: str | None) -> CharacterProfile:
    normalized_id = LEGACY_CHARACTER_ALIASES.get(character_id or "", character_id or "")
    return CHARACTERS.get(normalized_id, CHARACTERS[DEFAULT_CHARACTER_ID])


def expression_options(profile: CharacterProfile) -> str:
    expressions = profile.expressions or {}
    return ", ".join(f"{key}={value['label']}" for key, value in expressions.items())


def normalize_expression_id(character_id: str | None, expression_id: str | None) -> str:
    profile = get_character(character_id)
    expressions = profile.expressions or {}
    value = str(expression_id or "").strip().lower()
    return value if value in expressions else profile.default_expression_id


def auto_select_character(text: str) -> CharacterProfile:
    lowered = text.lower()
    scores = {"yoyo": 1, "momo": 0, "yoran": 0}
    keyword_rules = {
        "yoyo": [
            "难过", "伤心", "痛苦", "想哭", "崩溃", "孤独", "没人懂", "抑郁", "悲伤",
            "低落", "绝望", "自责", "羞耻", "委屈", "累", "疲惫", "害怕",
        ],
        "momo": [
            "怎么办", "行动", "下一步", "试试", "开始", "希望", "勇气", "边界",
            "拒绝", "保护", "撑住", "往前", "计划",
        ],
        "yoran": ["为什么", "分析", "看清", "逻辑", "模式", "关系", "矛盾", "困惑", "复盘", "理解", "整合"],
    }
    for character_id, keywords in keyword_rules.items():
        for keyword in keywords:
            if keyword in lowered or keyword in text:
                scores[character_id] += 2
    if "？" in text or "?" in text:
        scores["yoran"] += 1
    if "！" in text or "!" in text:
        scores["momo"] += 1
    selected_id = max(scores, key=lambda key: scores[key])
    return CHARACTERS[selected_id]


def list_characters() -> list[dict]:
    return [profile.to_public_dict() for profile in CHARACTERS.values()]
