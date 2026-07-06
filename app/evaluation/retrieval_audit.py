"""Run a privacy-preserving audit of memory and knowledge retrieval.

The audit reads a copy of the database and never emits message, memory, or
journal text. Reports contain aggregate metrics and opaque record identifiers.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from app.knowledge.retriever import KnowledgeRetriever, _query_tokens
from app.memory.schema import normalize_memory_subcategory
from app.memory.store import Store, tokenize_query


def _metadata(value: str) -> dict[str, Any]:
    try:
        parsed = json.loads(value or "{}")
    except (TypeError, json.JSONDecodeError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _conversation_cases(db_path: Path, sample_size: int) -> list[dict[str, Any]]:
    with sqlite3.connect(db_path) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT session_id, role, content, metadata, created_at
            FROM messages
            ORDER BY session_id, created_at, rowid
            """
        ).fetchall()

    cases: list[dict[str, Any]] = []
    for index, row in enumerate(rows):
        if row["role"] != "user":
            continue
        assistant_metadata: dict[str, Any] = {}
        for following in rows[index + 1:index + 4]:
            if following["session_id"] != row["session_id"]:
                break
            if following["role"] == "assistant":
                assistant_metadata = _metadata(following["metadata"])
                break
        route_plan = assistant_metadata.get("route_plan", {})
        if not isinstance(route_plan, dict):
            route_plan = {}
        cases.append(
            {
                "query": row["content"],
                "memory_terms": route_plan.get("memory_queries", []),
                "knowledge_terms": [
                    *route_plan.get("knowledge_needs", []),
                    *route_plan.get("knowledge_queries", []),
                ],
            }
        )
    return cases[-sample_size:]


def _distribution(
    hit_counts: Counter[str],
    all_ids: set[str],
    total_slots: int,
) -> dict[str, Any]:
    ranked = hit_counts.most_common()
    return {
        "covered": len(hit_counts),
        "never_hit": len(all_ids - set(hit_counts)),
        "coverage_rate": round(len(hit_counts) / max(1, len(all_ids)), 4),
        "top_10_slot_share": round(
            sum(count for _, count in ranked[:10]) / max(1, total_slots),
            4,
        ),
        "top_hits": [
            {"id": item_id, "hits": count}
            for item_id, count in ranked[:10]
        ],
    }


def _legacy_memory_relevant(
    store: Store,
    query: str,
    query_terms: list[str],
    limit: int = 5,
) -> list[dict[str, Any]]:
    tokens = list(dict.fromkeys([*tokenize_query(query), *query_terms]))
    if not tokens:
        return store.recent_memories(limit=limit)
    scored = []
    for memory in store.list_memories(limit=10000):
        if memory.get("status") != "active":
            continue
        keywords = memory.get("keywords", [])
        if not isinstance(keywords, list):
            keywords = []
        haystack = " ".join([
            memory.get("category", ""),
            memory.get("subcategory", ""),
            memory.get("content", ""),
            memory.get("evidence", ""),
            " ".join(str(keyword) for keyword in keywords),
        ])
        score = 0.0
        for token in tokens:
            if token in keywords:
                score += 4
            if token in memory.get("content", ""):
                score += 3
            if token in memory.get("evidence", ""):
                score += 2
            if token in haystack:
                score += 1
        if score > 0:
            score += float(memory.get("importance", 1)) * 0.2
            score += float(memory.get("confidence", 0.5)) * 0.2
            scored.append((score, memory))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [memory for _, memory in scored[:limit]]


def _legacy_memory_hybrid(
    store: Store,
    query: str,
    query_terms: list[str],
) -> list[dict[str, Any]]:
    result = _legacy_memory_relevant(store, query, query_terms)
    seen = {memory["id"] for memory in result}
    with store.connect() as conn:
        rows = conn.execute(
            """
            SELECT id, category, subcategory, keywords, content, evidence,
                   confidence, importance, status, updated_at
            FROM memories
            WHERE status = 'active'
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            (3 + len(seen),),
        ).fetchall()
    recent_added = 0
    for row in rows:
        item = dict(row)
        if item["id"] not in seen:
            result.append(item)
            seen.add(item["id"])
            recent_added += 1
        if recent_added >= 3:
            break
    return result[:10]


def _legacy_knowledge(
    knowledge: KnowledgeRetriever,
    query: str,
    query_terms: list[str],
) -> list[dict[str, Any]]:
    tokens = _query_tokens(query, None, query_terms)
    normalized_query = query.lower()
    scored = []
    for card in knowledge.list_cards():
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
        haystack = " ".join(str(value) for value in values).lower()
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
            if not direct_matches and (matched_tokens < 2 or score < 18):
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
    return [card for _, card in scored[:3]]


def run_audit(db_path: Path, sample_size: int = 250) -> dict[str, Any]:
    cases = _conversation_cases(db_path, sample_size)
    knowledge = KnowledgeRetriever()

    with tempfile.TemporaryDirectory(prefix="xiaolu-retrieval-audit-") as temp_dir:
        copied_db = Path(temp_dir) / "audit.db"
        shutil.copy2(db_path, copied_db)
        store = Store(str(copied_db))
        memories = [
            memory
            for memory in store.list_memories(limit=10000)
            if memory.get("status") == "active"
        ]

        memory_ids = {memory["id"] for memory in memories}
        card_ids = {card["id"] for card in knowledge.list_cards()}
        memory_meta = {memory["id"]: memory for memory in memories}
        card_meta = {card["id"]: card for card in knowledge.list_cards()}
        relevant_hits: Counter[str] = Counter()
        hybrid_hits: Counter[str] = Counter()
        card_hits: Counter[str] = Counter()
        legacy_relevant_hits: Counter[str] = Counter()
        legacy_hybrid_hits: Counter[str] = Counter()
        legacy_card_hits: Counter[str] = Counter()
        relevant_slots = hybrid_slots = card_slots = 0
        legacy_relevant_slots = legacy_hybrid_slots = legacy_card_slots = 0
        relevant_empty = hybrid_empty = card_empty = 0
        legacy_relevant_empty = legacy_hybrid_empty = legacy_card_empty = 0
        cases_with_route_terms = 0

        for case in cases:
            memory_terms = case["memory_terms"]
            knowledge_terms = case["knowledge_terms"]
            if memory_terms or knowledge_terms:
                cases_with_route_terms += 1
            relevant = store.search_memories(
                case["query"],
                query_terms=memory_terms,
                limit=5,
            )
            hybrid = store.search_memories_hybrid(
                case["query"],
                query_terms=memory_terms,
                relevant_limit=5,
                recent_limit=1,
                important_limit=2,
                important_threshold=5,
                total_limit=10,
            )
            cards = knowledge.retrieve(
                case["query"],
                query_terms=knowledge_terms,
                limit=3,
            )
            legacy_relevant = _legacy_memory_relevant(
                store,
                case["query"],
                memory_terms,
            )
            legacy_hybrid = _legacy_memory_hybrid(
                store,
                case["query"],
                memory_terms,
            )
            legacy_cards = _legacy_knowledge(
                knowledge,
                case["query"],
                knowledge_terms,
            )
            relevant_empty += not relevant
            hybrid_empty += not hybrid
            card_empty += not cards
            legacy_relevant_empty += not legacy_relevant
            legacy_hybrid_empty += not legacy_hybrid
            legacy_card_empty += not legacy_cards
            relevant_slots += len(relevant)
            hybrid_slots += len(hybrid)
            card_slots += len(cards)
            legacy_relevant_slots += len(legacy_relevant)
            legacy_hybrid_slots += len(legacy_hybrid)
            legacy_card_slots += len(legacy_cards)
            relevant_hits.update(item["id"] for item in relevant)
            hybrid_hits.update(item["id"] for item in hybrid)
            card_hits.update(item["id"] for item in cards)
            legacy_relevant_hits.update(item["id"] for item in legacy_relevant)
            legacy_hybrid_hits.update(item["id"] for item in legacy_hybrid)
            legacy_card_hits.update(item["id"] for item in legacy_cards)

        never_memory_by_category: Counter[str] = Counter()
        never_memory_by_importance: Counter[str] = Counter()
        for memory_id in memory_ids - set(relevant_hits):
            memory = memory_meta[memory_id]
            never_memory_by_category[str(memory.get("category", "unknown"))] += 1
            never_memory_by_importance[str(memory.get("importance", "unknown"))] += 1

        never_card_by_type: Counter[str] = Counter()
        for card_id in card_ids - set(card_hits):
            never_card_by_type[str(card_meta[card_id].get("concept_type", "unknown"))] += 1

        normalized_taxonomy: dict[str, Counter[str]] = defaultdict(Counter)
        for memory in memories:
            category = str(memory.get("category", "unknown"))
            normalized_taxonomy[category][normalize_memory_subcategory(
                category,
                memory.get("subcategory"),
            )] += 1

        historical_card_hits: Counter[str] = Counter()
        with sqlite3.connect(db_path) as conn:
            rows = conn.execute(
                "SELECT metadata FROM messages WHERE role = 'assistant'"
            ).fetchall()
        for (raw_metadata,) in rows:
            metadata = _metadata(raw_metadata)
            card_ids_used = metadata.get("knowledge_card_ids", [])
            if isinstance(card_ids_used, list):
                historical_card_hits.update(
                    str(card_id) for card_id in card_ids_used if card_id
                )

    memory_distribution = _distribution(
        relevant_hits,
        memory_ids,
        relevant_slots,
    )
    hybrid_distribution = _distribution(
        hybrid_hits,
        memory_ids,
        hybrid_slots,
    )
    card_distribution = _distribution(card_hits, card_ids, card_slots)
    legacy_relevant_distribution = _distribution(
        legacy_relevant_hits,
        memory_ids,
        legacy_relevant_slots,
    )
    legacy_hybrid_distribution = _distribution(
        legacy_hybrid_hits,
        memory_ids,
        legacy_hybrid_slots,
    )
    legacy_card_distribution = _distribution(
        legacy_card_hits,
        card_ids,
        legacy_card_slots,
    )
    for item in memory_distribution["top_hits"]:
        meta = memory_meta[item["id"]]
        item.update({
            "category": meta.get("category"),
            "importance": meta.get("importance"),
        })
    for item in hybrid_distribution["top_hits"]:
        meta = memory_meta[item["id"]]
        item.update({
            "category": meta.get("category"),
            "importance": meta.get("importance"),
        })
    for item in card_distribution["top_hits"]:
        meta = card_meta[item["id"]]
        item.update({
            "title": meta.get("title") or meta.get("name_zh"),
            "concept_type": meta.get("concept_type"),
        })

    return {
        "privacy": "aggregate_metrics_and_opaque_ids_only",
        "sample": {
            "queries": len(cases),
            "cases_with_route_terms": cases_with_route_terms,
        },
        "inventory": {
            "active_memories": len(memory_ids),
            "knowledge_cards": len(card_ids),
        },
        "legacy_comparison": {
            "memory_relevant": {
                "empty_rate": round(legacy_relevant_empty / max(1, len(cases)), 4),
                **legacy_relevant_distribution,
            },
            "memory_hybrid": {
                "empty_rate": round(legacy_hybrid_empty / max(1, len(cases)), 4),
                **legacy_hybrid_distribution,
            },
            "knowledge": {
                "empty_rate": round(legacy_card_empty / max(1, len(cases)), 4),
                **legacy_card_distribution,
            },
        },
        "memory_relevant": {
            "empty_rate": round(relevant_empty / max(1, len(cases)), 4),
            **memory_distribution,
            "never_hit_by_category": dict(never_memory_by_category),
            "never_hit_by_importance": dict(never_memory_by_importance),
        },
        "memory_hybrid": {
            "empty_rate": round(hybrid_empty / max(1, len(cases)), 4),
            **hybrid_distribution,
        },
        "knowledge": {
            "empty_rate": round(card_empty / max(1, len(cases)), 4),
            **card_distribution,
            "never_hit_by_concept_type": dict(never_card_by_type),
            "historical_card_coverage": len(historical_card_hits),
            "historical_card_uses": sum(historical_card_hits.values()),
        },
        "normalized_taxonomy": {
            category: dict(counts)
            for category, counts in sorted(normalized_taxonomy.items())
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default="data/app.db")
    parser.add_argument("--sample-size", type=int, default=250)
    parser.add_argument("--output")
    args = parser.parse_args()
    report = run_audit(Path(args.db), sample_size=max(1, args.sample_size))
    serialized = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)


if __name__ == "__main__":
    main()
