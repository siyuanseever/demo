import json
import re
from pathlib import Path
from typing import Any

from app.knowledge.document_cards import load_document_cards


CARD_PATH = Path(__file__).resolve().parent / "cards.json"
CONTENT_CARD_PATH = Path(__file__).resolve().parent / "content_cards.json"
SUPPLEMENTAL_CARD_PATH = Path(__file__).resolve().parent / "supplemental_cards.json"

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
    normalized.setdefault("medical_differential", "")
    normalized.setdefault("low_load_actions", [])
    normalized.setdefault("action_safety", "")
    normalized.setdefault("sources", [])
    return normalized


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


class KnowledgeRetriever:
    def __init__(self, path: Path = CARD_PATH) -> None:
        self.path = path
        base_cards = json.loads(path.read_text(encoding="utf-8"))
        document_cards = load_document_cards()
        supplemental_cards = json.loads(SUPPLEMENTAL_CARD_PATH.read_text(encoding="utf-8"))
        self.cards = [
            _normalize_card(card)
            for card in [*base_cards, *document_cards, *supplemental_cards]
        ]
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
            for token in tokens:
                if token and token in haystack:
                    score += 2 + min(len(token), 6)
            for keyword in [
                *card.get("tags", []),
                *card.get("aliases", []),
                *card.get("retrieval_triggers", []),
            ]:
                normalized_keyword = str(keyword).strip().lower()
                if normalized_keyword and normalized_keyword in normalized_query:
                    score += 5 + min(len(normalized_keyword), 8)
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


def render_knowledge_cards(cards: list[dict[str, Any]]) -> str:
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
                    "  替代解释：" + "；".join(card.get("differential_explanations", [])[:2]),
                    "  可选低负担动作：" + "；".join(card.get("low_load_actions", [])[:1]),
                    f"  动作安全：{card.get('action_safety', '')}",
                    f"  小鹿表达：{card['xiaolu_style']}",
                    f"  回应提示：{card['response_hint']}",
                    f"  来源：{card.get('source_ref') or card.get('source', '')}",
                ]
            )
        )
    return "\n".join(lines)
