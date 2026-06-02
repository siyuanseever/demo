import json
from pathlib import Path
from typing import Any


CARD_PATH = Path(__file__).resolve().parent / "cards.json"
CONTENT_CARD_PATH = Path(__file__).resolve().parent / "content_cards.json"


class KnowledgeRetriever:
    def __init__(self, path: Path = CARD_PATH) -> None:
        self.path = path
        self.cards = json.loads(path.read_text(encoding="utf-8"))
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

    def retrieve(
        self,
        query: str,
        *,
        memory_keywords: list[str] | None = None,
        query_terms: list[str] | None = None,
        limit: int = 3,
    ) -> list[dict[str, Any]]:
        tokens = set(memory_keywords or [])
        for term in query_terms or []:
            if str(term or "").strip():
                tokens.add(str(term).strip())
        for chunk in query.replace("，", " ").replace("。", " ").split():
            if chunk.strip():
                tokens.add(chunk.strip())
        scored = []
        for card in self.cards:
            haystack = " ".join(
                [
                    card["title"],
                    card["domain"],
                    " ".join(card["tags"]),
                    card["use_when"],
                    card["concept"],
                    card["response_hint"],
                ]
            )
            score = 0
            for token in tokens:
                if token and token in haystack:
                    score += 2
            for tag in card["tags"]:
                if tag in query or tag in tokens:
                    score += 3
            if score > 0:
                scored.append((score, card))
        scored.sort(key=lambda item: item[0], reverse=True)
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
                    f"  小鹿表达：{card['xiaolu_style']}",
                    f"  回应提示：{card['response_hint']}",
                ]
            )
        )
    return "\n".join(lines)
