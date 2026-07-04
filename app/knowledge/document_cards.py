import re
from pathlib import Path
from typing import Any


DOCUMENT_PATH = (
    Path(__file__).resolve().parents[2]
    / "docs"
    / "心理学知识卡片与检索系统资料库.md"
)

SECTION_PATTERN = re.compile(
    r"^## (?P<section>(?:[2-9]|1[0-3])\.\d+|H[1-7])"
    r"(?:[：\s]+)(?P<title>.+?)\s*$",
    re.MULTILINE,
)

CATEGORY_BY_CHAPTER = {
    "2": "trauma_and_threat",
    "3": "nervous_system",
    "4": "load_and_exhaustion",
    "5": "dissociation_and_avoidance",
    "6": "self_monitoring",
    "7": "attachment",
    "8": "meaning_and_values",
    "9": "cognition",
    "10": "shame_and_identity",
    "11": "mind_body",
    "12": "therapeutic_framework",
    "13": "recovery_and_flow",
    "H": "personalized_hypothesis",
}

WORKING_CONCEPT_SECTIONS = {
    "2.6",
    "2.7",
    "5.3",
    "6.1",
    "6.4",
    "8.5",
    "10.3",
    "13.2",
}
CONTESTED_THEORY_SECTIONS = {"3.6"}
CLINICAL_CONCEPT_SECTIONS = {
    "4.6",
    "5.1",
    "5.2",
    "6.5",
    "10.5",
    "11.1",
}
BODY_RELATED_SECTIONS = {"3.1", "3.2", "3.3", "3.4", "4.1", "4.2", "4.5", "11.1", "11.2", "11.3"}
SECTION_ALIASES = {
    "3.6": ["背侧迷走神经强制关机", "Dorsal Vagal Shutdown"],
}

SEARCH_TERMS = (
    "安全感",
    "警觉",
    "焦虑",
    "冻结",
    "撤退",
    "不出门",
    "脑雾",
    "眼睛",
    "疲劳",
    "耗竭",
    "复杂",
    "黑箱",
    "比较",
    "自卑",
    "羞耻",
    "自责",
    "关系",
    "回复",
    "拒绝",
    "讨厌",
    "依恋",
    "孤独",
    "工作",
    "面试",
    "失业",
    "剥削",
    "控制",
    "游戏",
    "回避",
    "麻木",
    "解离",
    "身体",
    "心慌",
    "睡眠",
    "药物",
    "反刍",
    "读心",
    "灾难化",
    "价值",
    "意义",
    "身份",
    "容貌",
    "休息",
    "恢复",
    "心流",
    "沉浸",
    "注意力",
)


def _concept_type(section: str) -> str:
    if section.startswith("H"):
        return "personalized_hypothesis"
    if section in WORKING_CONCEPT_SECTIONS:
        return "working_concept"
    if section in CONTESTED_THEORY_SECTIONS:
        return "contested_theory"
    if section.startswith("12."):
        return "therapeutic_framework"
    if section in CLINICAL_CONCEPT_SECTIONS:
        return "clinical_concept"
    return "established_concept"


def _card_role(section: str) -> str:
    if section.startswith("H"):
        return "personalized_pattern"
    if section.startswith("12."):
        return "therapeutic_framework"
    return "mechanism"


def _evidence_level(concept_type: str) -> str:
    return {
        "personalized_hypothesis": "working_hypothesis",
        "working_concept": "working_hypothesis",
        "contested_theory": "contested",
        "therapeutic_framework": "widely_used_framework",
        "clinical_concept": "clinical_construct",
        "established_concept": "established_or_widely_used",
    }[concept_type]


def _clean_markdown(text: str) -> str:
    text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    text = re.sub(r"^#{3,6}\s+.*$", " ", text, flags=re.MULTILINE)
    text = re.sub(r"^[>\-\d.]+\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"[*_`]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def _summary(body: str) -> str:
    clean = _clean_markdown(body)
    if len(clean) <= 260:
        return clean
    stop = max(clean.rfind("。", 0, 260), clean.rfind("；", 0, 260))
    return clean[: stop + 1 if stop >= 80 else 260].strip()


def _bullet_phrases(body: str) -> list[str]:
    phrases = []
    for raw_line in body.splitlines():
        line = raw_line.strip()
        if not line.startswith("- "):
            continue
        phrase = _clean_markdown(line[2:])
        if 2 <= len(phrase) <= 36 and phrase not in phrases:
            phrases.append(phrase)
    return phrases[:18]


def _aliases(title: str) -> list[str]:
    aliases = []
    for part in re.split(r"\s*/\s*|\s{2,}", title):
        value = part.strip()
        if value and value not in aliases:
            aliases.append(value)
    english = re.findall(r"[A-Za-z][A-Za-z -]+", title)
    aliases.extend(item.strip() for item in english if item.strip() not in aliases)
    return aliases[:8]


def _tags(title: str, body: str) -> list[str]:
    haystack = f"{title} {body}"
    tags = [term for term in SEARCH_TERMS if term in haystack]
    return tags[:16]


def _differential_explanations(section: str) -> list[str]:
    alternatives = [
        "当前现实情境本身也可能确有压力、拒绝、不公或信息不足，需要结合事实判断。",
        "睡眠、近期负荷、生活变化和其他身体状态也可能共同影响体验。",
    ]
    if section in BODY_RELATED_SECTIONS:
        alternatives.append(
            "身体症状还应保留视觉疲劳、药物、贫血、心血管、内分泌或其他疾病等医学解释。"
        )
    return alternatives


def _evidence_caveat(section: str, concept_type: str) -> str:
    if concept_type == "personalized_hypothesis":
        return "这是用于探索长期体验的个体化工作假设，不是诊断，也不是已经确认的用户事实。"
    if concept_type == "working_concept":
        return "这是本项目用于组织体验的工作性概念，不是标准诊断术语。"
    if concept_type == "contested_theory":
        return "该理论在实践中有影响，但部分核心主张存在科学争议，只可作为启发式框架。"
    if section == "11.3":
        return "“身体记忆”应作为描述性说法使用，不能声称身体精确储存了某段记忆。"
    return "该卡片提供可能的解释框架，不能单独用于判断原因或作出诊断。"


def _card_id(section: str) -> str:
    return f"psych-library-{section.lower().replace('.', '-')}"


def load_document_cards(path: Path = DOCUMENT_PATH) -> list[dict[str, Any]]:
    """Turn the user-provided psychology library into runtime knowledge cards."""
    if not path.exists():
        return []

    text = path.read_text(encoding="utf-8")
    matches = list(SECTION_PATTERN.finditer(text))
    cards = []
    for index, match in enumerate(matches):
        section = match.group("section")
        next_card_start = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        next_chapter = re.search(r"^# \d+\.", text[match.end():], flags=re.MULTILINE)
        next_chapter_start = (
            match.end() + next_chapter.start()
            if next_chapter
            else len(text)
        )
        body_end = min(next_card_start, next_chapter_start)
        body = text[match.end():body_end].strip()
        title = match.group("title").strip()
        concept_type = _concept_type(section)
        chapter = "H" if section.startswith("H") else section.split(".", 1)[0]
        aliases = _aliases(title)
        aliases.extend(alias for alias in SECTION_ALIASES.get(section, []) if alias not in aliases)
        card = {
            "id": _card_id(section),
            "title": title,
            "name_zh": re.split(r"\s+[A-Za-z]", title, maxsplit=1)[0].strip(" /"),
            "name_en": " / ".join(re.findall(r"[A-Za-z][A-Za-z /-]+", title)).strip(),
            "aliases": aliases,
            "domain": CATEGORY_BY_CHAPTER[chapter],
            "category": [CATEGORY_BY_CHAPTER[chapter]],
            "taxonomy_path": [CATEGORY_BY_CHAPTER[chapter]],
            "card_role": _card_role(section),
            "concept_type": concept_type,
            "evidence_level": _evidence_level(concept_type),
            "diagnosis_required": False,
            "tags": _tags(title, body),
            "retrieval_triggers": _bullet_phrases(body),
            "use_when": "当用户的具体体验、身体感受、想法或关系情境与本卡描述相近时，用作候选解释。",
            "avoid_when": "证据不足时不要把候选机制写成事实、人格标签或临床诊断。",
            "concept": _summary(body),
            "full_content": body,
            "xiaolu_style": "先回应体验，再以“可能”“也许”提出这个视角，并邀请用户核对是否贴近。",
            "response_hint": "区分已知事实、用户解释与机制假设；优先恢复选择权和主体判断。",
            "response_guidance": [
                "先确认用户当前体验和现实处境。",
                "把本卡作为可核对的可能性，而不是结论。",
                "给建议前先判断认知资源与用户是否想行动。",
            ],
            "anti_patterns": [
                "不得据此诊断或给用户贴标签。",
                "不得用心理学解释否定现实中的拒绝、不公、剥削或身体问题。",
                "不得使用童年、创伤等单一原因解释全部体验。",
            ],
            "differential_explanations": _differential_explanations(section),
            "medical_differential": (
                _differential_explanations(section)[-1]
                if section in BODY_RELATED_SECTIONS
                else ""
            ),
            "related_cards": [],
            "low_load_actions": [],
            "action_safety": "",
            "evidence_caveat": _evidence_caveat(section, concept_type),
            "source": "用户提供的心理学知识资料库 v0.1",
            "source_ref": f"《心理学知识卡片与检索系统资料库》§{section}",
            "source_section": section,
        }
        cards.append(card)
    for card in cards:
        card_tags = set(card["tags"])
        related = []
        for candidate in cards:
            if candidate["id"] == card["id"]:
                continue
            shared_tags = card_tags.intersection(candidate["tags"])
            score = len(shared_tags) * 3
            if candidate["domain"] == card["domain"]:
                score += 1
            if score > 0:
                related.append((score, candidate["id"]))
        related.sort(key=lambda item: (item[0], item[1]), reverse=True)
        card["related_cards"] = [card_id for _, card_id in related[:4]]
    return cards
