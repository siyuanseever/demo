import json
import re
from pathlib import Path
from typing import Any

from app.knowledge.document_cards import load_document_cards


CARD_PATH = Path(__file__).resolve().parent / "cards.json"
CONTENT_CARD_PATH = Path(__file__).resolve().parent / "content_cards.json"
SUPPLEMENTAL_CARD_PATH = Path(__file__).resolve().parent / "supplemental_cards.json"
CURATED_OVERRIDE_PATH = Path(__file__).resolve().parent / "curated_retrieval_overrides.json"

EMOTION_TERMS = ("焦虑", "害怕", "羞耻", "自卑", "愤怒", "委屈", "孤独", "麻木", "低落", "烦")
BODY_TERMS = ("心慌", "胸闷", "心跳", "呼吸", "手臂", "肌肉", "眼睛", "脑雾", "头晕", "疲劳", "累", "疼", "睡不着")
URGE_TERMS = ("想逃", "想躲", "想追问", "想证明", "想放弃", "想打游戏", "想消失")
BEHAVIOR_TERMS = ("不出门", "取消", "刷新消息", "反复检查", "打游戏", "躺着", "追问", "回避")
CONTEXT_TERMS = {
    "work": ("工作", "公司", "领导", "面试", "同事", "求职", "失业", "Agent"),
    "relationship": ("关系", "她", "他", "回复", "消息", "喜欢", "讨厌", "疏远", "暧昧"),
    "family": ("父母", "妈妈", "爸爸", "家庭", "家里"),
    "health": ("身体", "药", "医院", "睡眠", "疼", "心慌", "胸闷"),
    "living": ("住处", "搬家", "房租", "城市"),
}

QUERY_EXPANSIONS = {
    "没回": ["不回复", "回复变慢", "关系不确定", "拒绝"],
    "不回": ["不回复", "回复变慢", "关系不确定", "拒绝"],
    "讨厌我": ["厌烦", "拒绝", "读心", "关系不确定"],
    "眼睛累": ["眼睛疲劳", "视觉疲劳", "感觉过载", "认知负荷"],
    "脑袋不在线": ["脑雾", "认知负荷", "低唤醒"],
    "很复杂": ["复杂系统", "黑箱", "社会比较", "能力评价"],
    "觉得自己很差": ["自卑", "羞耻", "条件性自我价值", "向上比较"],
    "没出门": ["不出门", "撤退", "耗竭", "低唤醒"],
    "什么都不想做": ["无力", "麻木", "撤退", "耗竭"],
    "放松不下来": ["无法放松", "持续警戒", "高唤醒", "未决感"],
    "找不到工作": ["失业", "灾难化", "身份威胁", "合理担忧"],
    "剥削": ["不公", "控制型领导", "工作", "现实证据"],
    "打游戏": ["游戏", "自我冬眠", "恢复性活动", "体验性回避"],
    "背侧迷走": ["多迷走神经理论", "撤退", "低唤醒", "争议"],
    "一直看我": ["聚光灯效应", "自我监控", "内化的他者视角"],
    "自动赞同": ["讨好", "安抚", "顺从", "权力差异"],
    "一直刷新": ["异步等待", "反刍", "关系不确定", "检查消息"],
    "手臂": ["肌肉紧张", "压力", "脑子空白", "执行功能"],
    "缓不过来": ["压力残留", "场景切换", "持续紧张", "恢复"],
    "重被子": ["深压觉急救", "外部定向", "肌肉释放", "Grounding"],
}


def _normalize_card(card: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(card)
    normalized.setdefault("name_zh", card.get("title", ""))
    normalized.setdefault("name_en", "")
    normalized.setdefault("aliases", [])
    normalized.setdefault("category", [card.get("domain", "general")])
    normalized.setdefault("taxonomy_path", normalized["category"])
    normalized.setdefault("card_role", "mechanism")
    normalized.setdefault("concept_type", "established_concept")
    normalized.setdefault("evidence_level", "unspecified")
    normalized.setdefault("diagnosis_required", False)
    normalized.setdefault(
        "risk_of_overpathologizing",
        "medium"
        if normalized["concept_type"] in {
            "clinical_concept",
            "working_concept",
            "personalized_hypothesis",
        }
        else "low",
    )
    normalized.setdefault("retrieval_triggers", [])
    normalized.setdefault("related_cards", [])
    normalized.setdefault("differential_explanations", [
        "当前现实情境、身体状态和近期压力也可能参与，需要结合具体证据判断。"
    ])
    normalized.setdefault("response_guidance", [card.get("response_hint", "")])
    normalized.setdefault("anti_patterns", [
        "不得把知识卡直接用于诊断，也不得把候选解释写成用户事实。"
    ])
    normalized.setdefault(
        "evidence_caveat",
        "该卡片仅提供可能的解释框架，不能单独用于判断原因或作出诊断。",
    )
    normalized.setdefault("source_ref", card.get("source", ""))
    medical_differential = normalized.get("medical_differential", [])
    if isinstance(medical_differential, str):
        medical_differential = [medical_differential] if medical_differential.strip() else []
    normalized["medical_differential"] = medical_differential
    normalized.setdefault("low_load_actions", [])
    normalized.setdefault("action_safety", "")
    normalized.setdefault("sources", [])
    return normalized


def _merge_unique(existing: list[Any], additions: list[Any]) -> list[Any]:
    merged = list(existing)
    for item in additions:
        if item not in merged:
            merged.append(item)
    return merged


def _apply_overrides(
    cards: list[dict[str, Any]],
    overrides: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    merged_cards = []
    for card in cards:
        merged = dict(card)
        override = overrides.get(card["id"], {})
        for key, value in override.items():
            if isinstance(value, list):
                merged[key] = _merge_unique(merged.get(key, []), value)
            else:
                merged[key] = value
        merged_cards.append(merged)
    return merged_cards


def _search_text(card: dict[str, Any]) -> str:
    values = [
        card.get("title", ""),
        card.get("name_zh", ""),
        card.get("name_en", ""),
        card.get("domain", ""),
        card.get("use_when", ""),
        card.get("concept", ""),
        card.get("full_content", ""),
        *card.get("aliases", []),
        *card.get("tags", []),
        *card.get("retrieval_triggers", []),
    ]
    return " ".join(str(value) for value in values).lower()


def _query_tokens(
    query: str,
    memory_keywords: list[str] | None,
    query_terms: list[str] | None,
) -> set[str]:
    raw_terms = [query, *(memory_keywords or []), *(query_terms or [])]
    tokens = {
        token.strip().lower()
        for value in raw_terms
        for token in re.split(r"[\s，。！？、；：,.!?;:（）()\"“”]+", str(value or ""))
        if token.strip()
    }
    normalized_query = query.lower()
    for phrase, expansions in QUERY_EXPANSIONS.items():
        if phrase in normalized_query:
            tokens.update(expansions)
    return tokens


def _matching_terms(query: str, terms: tuple[str, ...]) -> list[str]:
    return [term for term in terms if term.lower() in query.lower()]


def extract_query_state(query: str) -> dict[str, Any]:
    normalized = str(query or "").strip()
    emotions = _matching_terms(normalized, EMOTION_TERMS)
    body = _matching_terms(normalized, BODY_TERMS)
    urges = _matching_terms(normalized, URGE_TERMS)
    behaviors = _matching_terms(normalized, BEHAVIOR_TERMS)
    context = {
        name: next((term for term in terms if term.lower() in normalized.lower()), None)
        for name, terms in CONTEXT_TERMS.items()
    }
    thought_markers = ("是不是", "一定", "永远", "彻底", "我很差", "我不行", "没希望")
    thoughts = [
        chunk.strip()
        for chunk in re.split(r"[，。！？!?]", normalized)
        if chunk.strip() and any(marker in chunk for marker in thought_markers)
    ][:4]
    high_arousal = any(
        term in normalized
        for term in ("焦虑", "心慌", "紧张", "警惕", "停不下来", "害怕", "愤怒")
    )
    low_arousal = any(
        term in normalized
        for term in ("麻木", "无力", "脑雾", "什么都不想做", "不想出门", "掉线")
    )
    if high_arousal and low_arousal:
        arousal_guess = "mixed"
    elif high_arousal:
        arousal_guess = "high"
    elif low_arousal:
        arousal_guess = "low"
    else:
        arousal_guess = "unknown"
    time_match = re.search(r"(几分钟|几小时|\d+\s*小时|\d+\s*天|几天|几周|一直|长期)", normalized)
    uncertainty_level = (
        "high"
        if any(term in normalized for term in ("是不是", "不知道", "不确定", "可能", "会不会"))
        else "unknown"
    )
    return {
        "event": normalized,
        "emotion": emotions,
        "body": body,
        "thought": thoughts,
        "urge": urges,
        "behavior": behaviors,
        "context": context,
        "arousal_guess": arousal_guess,
        "uncertainty_level": uncertainty_level,
        "time_course": time_match.group(1) if time_match else "unknown",
        "cognitive_capacity": (
            "low"
            if any(term in normalized for term in ("脑子空白", "脑袋不在线", "无法思考", "崩溃", "过载"))
            else "unknown"
        ),
    }


class KnowledgeRetriever:
    def __init__(self, path: Path = CARD_PATH) -> None:
        self.path = path
        base_cards = json.loads(path.read_text(encoding="utf-8"))
        document_cards = load_document_cards()
        supplemental_cards = json.loads(SUPPLEMENTAL_CARD_PATH.read_text(encoding="utf-8"))
        overrides = json.loads(CURATED_OVERRIDE_PATH.read_text(encoding="utf-8"))
        normalized_cards = [
            _normalize_card(card)
            for card in [*base_cards, *document_cards, *supplemental_cards]
        ]
        self.cards = _apply_overrides(normalized_cards, overrides)
        self.content_cards = json.loads(CONTENT_CARD_PATH.read_text(encoding="utf-8"))

    def list_cards(self) -> list[dict[str, Any]]:
        return self.cards

    def list_content_cards(self) -> list[dict[str, Any]]:
        return self.content_cards

    def get_card(self, card_id: str) -> dict[str, Any] | None:
        return next((card for card in self.cards if card["id"] == card_id), None)

    def related_content_for_knowledge(self, card_id: str) -> list[dict[str, Any]]:
        return [
            card
            for card in self.content_cards
            if card_id in card.get("related_knowledge_ids", [])
        ]

    def related_cards_for_knowledge(self, card_id: str) -> list[dict[str, Any]]:
        card = self.get_card(card_id)
        if not card:
            return []
        related_ids = card.get("related_cards", [])
        return [
            related
            for related_id in related_ids
            if (related := self.get_card(related_id))
        ]

    def retrieve(
        self,
        query: str,
        *,
        memory_keywords: list[str] | None = None,
        query_terms: list[str] | None = None,
        limit: int = 3,
    ) -> list[dict[str, Any]]:
        if limit <= 0:
            return []
        tokens = _query_tokens(query, memory_keywords, query_terms)
        normalized_query = query.lower()
        scored = []
        for card in self.cards:
            haystack = _search_text(card)
            score = 0
            matched_tokens = 0
            for token in tokens:
                if token and token in haystack:
                    score += 2 + min(len(token), 6)
                    matched_tokens += 1
            direct_matches = 0
            for keyword in [
                *card.get("tags", []),
                *card.get("aliases", []),
                *card.get("retrieval_triggers", []),
            ]:
                normalized_keyword = str(keyword).strip().lower()
                if normalized_keyword and normalized_keyword in normalized_query:
                    score += 5 + min(len(normalized_keyword), 8)
                    direct_matches += 1
            if card.get("concept_type") == "personalized_hypothesis":
                has_history_support = any(
                    str(keyword or "").strip().lower() in haystack
                    for keyword in memory_keywords or []
                    if str(keyword or "").strip()
                )
                if not direct_matches and not has_history_support and (
                    matched_tokens < 2 or score < 18
                ):
                    continue
                score -= 6
            if score > 0:
                scored.append((score, card))
        scored.sort(
            key=lambda item: (
                item[0],
                item[1].get("source_section", ""),
                item[1].get("title", ""),
            ),
            reverse=True,
        )
        return [card for _, card in scored[:limit]]

    def retrieve_plan(
        self,
        query: str,
        *,
        memory_keywords: list[str] | None = None,
        query_terms: list[str] | None = None,
        limit: int = 3,
    ) -> dict[str, Any]:
        state = extract_query_state(query)
        primary_cards = self.retrieve(
            query,
            memory_keywords=memory_keywords,
            query_terms=query_terms,
            limit=limit,
        )
        alternatives = []
        rejected = []
        medical_differential = []
        for card in primary_cards:
            alternatives = _merge_unique(
                alternatives,
                card.get("differential_explanations", []),
            )
            rejected = _merge_unique(rejected, card.get("anti_patterns", []))
            medical_differential = _merge_unique(
                medical_differential,
                card.get("medical_differential", []),
            )
        if not alternatives:
            alternatives = [
                "当前信息仍有限，也可能主要由现实情境、近期负荷或尚未提到的因素造成。"
            ]
        if state["body"] and not medical_differential:
            medical_differential = [
                "睡眠、药物、营养、疼痛、视觉疲劳或其他身体因素",
                "症状持续、异常或加重时需要医学评估",
            ]
        safety_flags = []
        if state["body"]:
            safety_flags.append("preserve_medical_differential")
        if state["cognitive_capacity"] == "low":
            safety_flags.append("low_cognitive_capacity")
        if any(card.get("concept_type") == "personalized_hypothesis" for card in primary_cards):
            safety_flags.append("personalized_hypothesis_not_fact")
        if any(card.get("concept_type") == "contested_theory" for card in primary_cards):
            safety_flags.append("contested_theory_requires_caveat")
        response_strategy = [
            "先复述可观察事实和用户体验，不急着解释。",
            "只选择最贴近的一个核心视角自然表达，其余卡片作为内部校验。",
            "明确区分已知事实、用户解释和候选机制。",
            "至少保留一个现实、身体或其他替代解释。",
            "只有用户资源允许时，提供一个可选且可停止的低负担动作。",
        ]
        return {
            "extracted_state": state,
            "primary_cards": primary_cards,
            "alternative_explanations": alternatives[:4],
            "medical_differential": medical_differential[:6],
            "rejected_overinterpretations": rejected[:4],
            "response_strategy": response_strategy,
            "safety_flags": safety_flags,
        }


def render_knowledge_cards(
    cards: list[dict[str, Any]],
    plan: dict[str, Any] | None = None,
) -> str:
    if not cards:
        return "暂无可用知识卡。"
    lines = []
    for card in cards:
        lines.append(
            "\n".join(
                [
                    f"- {card['title']}（{card['domain']}）",
                    f"  适用：{card['use_when']}",
                    f"  概念：{card['concept']}",
                    f"  类型：{card.get('concept_type', 'established_concept')}",
                    f"  卡片角色：{card.get('card_role', 'mechanism')}",
                    f"  证据等级：{card.get('evidence_level', 'unspecified')}",
                    f"  证据边界：{card.get('evidence_caveat', '')}",
                    f"  过度病理化风险：{card.get('risk_of_overpathologizing', 'medium')}",
                    "  可选低负担动作：" + "；".join(card.get("low_load_actions", [])[:1]),
                    f"  动作安全：{card.get('action_safety', '')}",
                    f"  小鹿表达：{card['xiaolu_style']}",
                    f"  回应提示：{card['response_hint']}",
                    f"  来源：{card.get('source_ref') or card.get('source', '')}",
                ]
            )
        )
    if plan:
        lines.extend([
            "\n本轮检索计划：",
            "- 状态抽取：" + json.dumps(
                plan.get("extracted_state", {}),
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            "- 必须保留的替代解释：" + "；".join(plan.get("alternative_explanations", [])),
            "- 身体/医学鉴别：" + "；".join(plan.get("medical_differential", [])),
            "- 拒绝的过度解读：" + "；".join(plan.get("rejected_overinterpretations", [])),
            "- 安全标记：" + "、".join(plan.get("safety_flags", [])),
        ])
    return "\n".join(lines)
