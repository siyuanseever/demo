import json
import logging
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from app.agents.safety import CRISIS_RESPONSE, detect_crisis
from app.characters import (
    CHARACTERS,
    auto_select_character,
    expression_options,
    get_character,
    normalize_expression_id,
)
from app.config import get_settings
from app.intent.agent import IntentAgent
from app.intent.router import IntentRouter
from app.llm.base import LLMClient
from app.knowledge.retriever import KnowledgeRetriever, render_knowledge_cards
from app.memory.schema import (
    MEMORY_CATEGORIES,
    STATE_PROFILE_DOMAINS,
    STATE_PROFILE_TRENDS,
    normalize_memory_subcategory,
)
from app.memory.store import Store


PROMPT_DIR = Path(__file__).resolve().parents[1] / "prompts"


RISK_LEVELS = {"low", "medium", "high"}
RESPONSE_MODES = {"stabilize", "validate", "insight", "boundary", "action", "mixed"}


def read_prompt(name: str) -> str:
    return (PROMPT_DIR / name).read_text(encoding="utf-8")


def parse_json_object(content: str) -> dict:
    text = str(content or "").strip()
    if not text:
        return {}
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            return {}
        try:
            payload = json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            return {}
    if not isinstance(payload, dict):
        return {}
    return payload


def render_quick_reply_handoff(quick_reply_text: str | None) -> str:
    quick_reply = str(quick_reply_text or "").strip()[:1200]
    if not quick_reply:
        return ""
    return read_prompt("quick_reply_handoff.md").format(quick_reply_text=quick_reply)


def render_memories(memories: list) -> str:
    if not memories:
        return "暂无长期记忆。"
    lines = []
    for memory in memories:
        keywords = memory.get("keywords", [])
        if isinstance(keywords, str):
            try:
                keywords = json.loads(keywords)
            except json.JSONDecodeError:
                keywords = []
        if not isinstance(keywords, list):
            keywords = []

        evidence = memory.get("evidence", "")
        if isinstance(evidence, list):
            evidence = "、".join(str(item) for item in evidence)
        elif not isinstance(evidence, str):
            evidence = str(evidence)

        lines.append(
            f"- [{memory['category']}/{memory['subcategory']}] {memory['content']}"
            f"（关键词：{'、'.join(str(keyword) for keyword in keywords)}；证据：{evidence}）"
        )
    return "\n".join(lines)


def render_state_profiles(profiles: list[dict]) -> str:
    if not profiles:
        return "暂无长期状态画像。"
    lines = []
    for profile in profiles:
        evidence = profile.get("evidence", [])
        if isinstance(evidence, list):
            evidence_text = "；".join(str(item) for item in evidence[:3])
        else:
            evidence_text = ""
        lines.append(
            f"- [{profile.get('domain', '')}] {profile.get('stage', '')}：{profile.get('summary', '')}"
            f"（强度：{profile.get('intensity', '-')}/10；趋势：{profile.get('trend', '')}；"
            f"置信度：{profile.get('confidence', '-')}; 策略：{profile.get('support_strategy', '')}；"
            f"证据：{evidence_text or '暂无'}）"
        )
    return "\n".join(lines)


def render_state_profile_history(versions: list[dict]) -> str:
    if not versions:
        return "暂无长期状态历史版本。"
    lines = []
    for version in versions[:18]:
        evidence = version.get("evidence", [])
        if isinstance(evidence, list):
            evidence_text = "；".join(str(item) for item in evidence[:2])
        else:
            evidence_text = ""
        lines.append(
            f"- {version.get('created_at', '')} [{version.get('domain', '')}] "
            f"{version.get('stage', '')}（趋势：{version.get('trend', '')}；"
            f"强度：{version.get('intensity', '-')}/10；action：{version.get('action', '')}；"
            f"证据：{evidence_text or '暂无'}）"
        )
    return "\n".join(lines)


def message_character_name(row) -> str:
    metadata = {}
    try:
        metadata = json.loads(row["metadata"] or "{}")
    except (KeyError, TypeError, json.JSONDecodeError):
        metadata = {}
    return get_character(metadata.get("character_id")).name


def render_conversation_history(messages: list) -> str:
    if not messages:
        return "暂无历史对话。"
    lines = []
    for row in messages[-12:]:
        if row["role"] == "user":
            speaker = "用户"
        else:
            speaker = message_character_name(row)
        lines.append(f"{speaker}：{row['content']}")
    return "\n".join(lines)


def render_character_options() -> str:
    lines = []
    for profile in CHARACTERS.values():
        lines.append(
            f"- {profile.id}: {profile.name}（{profile.animal}）"
            f"；气质：{profile.tagline}；声音：{profile.voice}"
            f"；可用表情：{expression_options(profile)}"
        )
    return "\n".join(lines)


def _short_text(value: object, fallback: str, limit: int) -> str:
    text = str(value or "").strip()
    if not text:
        text = fallback
    return text[:limit]


def _normalize_choice(value: object, allowed: set[str], fallback: str) -> str:
    text = str(value or "").strip().lower()
    return text if text in allowed else fallback


def _normalize_query_terms(value: object, limit: int = 6) -> list[str]:
    if not isinstance(value, list):
        return []
    terms = []
    for item in value:
        text = str(item or "").strip()
        if text and text not in terms:
            terms.append(text[:32])
    return terms[:limit]


def normalize_response_plan(raw_plan: dict, fallback_character_id: str) -> dict:
    if not isinstance(raw_plan, dict):
        raw_plan = {}
    character_id = str(raw_plan.get("character_id") or raw_plan.get("form_id") or fallback_character_id).strip()
    if character_id not in CHARACTERS:
        character_id = fallback_character_id if fallback_character_id in CHARACTERS else auto_select_character("").id
    expression_id = normalize_expression_id(character_id, raw_plan.get("expression_id"))
    history_turns = raw_plan.get("history_turns_needed", 5)
    try:
        history_turns = max(0, min(20, int(history_turns)))
    except (TypeError, ValueError):
        history_turns = 5
    context_strategy = _normalize_choice(raw_plan.get("context_strategy"), ["focus_current", "balanced", "history_heavy"], "balanced")
    return {
        "user_state": _short_text(raw_plan.get("user_state"), "需要进一步理解用户此刻状态。", 60),
        "core_need": _short_text(raw_plan.get("core_need"), "被接住，并获得一点清晰感。", 60),
        "risk_level": _normalize_choice(raw_plan.get("risk_level"), RISK_LEVELS, "low"),
        "response_mode": _normalize_choice(raw_plan.get("response_mode"), RESPONSE_MODES, "mixed"),
        "knowledge_needs": _normalize_query_terms(raw_plan.get("knowledge_needs"), limit=5),
        "memory_queries": _normalize_query_terms(raw_plan.get("memory_queries"), limit=6),
        "knowledge_queries": _normalize_query_terms(raw_plan.get("knowledge_queries"), limit=6),
        "response_guidance": _short_text(
            raw_plan.get("response_guidance"),
            "先承接，再给出克制的心理学解释；避免替用户下过重结论。",
            140,
        ),
        "character_id": character_id,
        "expression_id": expression_id,
        "reason": str(raw_plan.get("reason") or "根据用户当前表达的情绪强度、问题类型和需要的支持方式选择。")[:160],
        "history_turns_needed": history_turns,
        "need_state_profiles": bool(raw_plan.get("need_state_profiles", True)),
        "need_more_memories": bool(raw_plan.get("need_more_memories", False)),
        "context_strategy": context_strategy,
    }


def render_role_plan(route_plan: dict | None) -> str:
    if not route_plan:
        return "本轮是手动形态回复。不要加入其他动物或其他形态的短句。"
    if "character_id" in route_plan:
        character = get_character(route_plan["character_id"])
        expression_id = normalize_expression_id(character.id, route_plan.get("expression_id"))
        expression = (character.expressions or {}).get(expression_id, {})
        return (
            "本轮是单一兔子形态回复，不要加入多角色短句，也不要让不同形态互相聊天。\n"
            "本轮策略规划：\n"
            f"- 用户状态：{route_plan['user_state']}\n"
            f"- 核心需要：{route_plan['core_need']}\n"
            f"- 风险等级：{route_plan['risk_level']}\n"
            f"- 回复模式：{route_plan['response_mode']}\n"
            f"- 选择形态：{character.name}（{character.animal}）\n"
            f"- 选择表情：{expression_id}（{expression.get('label', expression_id)}）\n"
            f"- 知识需求：{'、'.join(route_plan['knowledge_needs']) if route_plan['knowledge_needs'] else '暂无明确知识卡需求'}\n"
            f"- 写作提醒：{route_plan['response_guidance']}\n"
            f"- 选择理由：{route_plan['reason']}\n"
        )
    return "本轮是单一兔子形态回复。"


def render_rabbit_response_instruction(route_plan: dict) -> str:
    character = get_character(route_plan["character_id"])
    expression_id = normalize_expression_id(character.id, route_plan.get("expression_id"))
    opts = expression_options(character)
    return "\n\n" + read_prompt("rabbit_response_instruction.md").format(
        character_name=character.name,
        expression_id=expression_id,
        expression_options=opts,
    )


def preview_text(text: str, limit: int = 3000) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n...（已截断，原始长度 {len(text)} 字符）"


class ConversationOrchestrator:
    def __init__(self, llm: LLMClient, store: Store) -> None:
        self.llm = llm
        self.store = store
        self.knowledge = KnowledgeRetriever()
        self.logger = logging.getLogger(__name__)
        settings = get_settings()
        self.quick_reply_max_tokens = settings.quick_reply_max_tokens
        self.quick_reply_history_turns = settings.quick_reply_history_turns
        self.quick_reply_history_chars = settings.quick_reply_history_chars
        self.intent_agent = IntentAgent(
            llm,
            confidence_threshold=settings.intent_confidence_threshold,
            max_history_turns=5,
            max_tokens=settings.intent_quick_max_tokens,
        )
        self.intent_router = IntentRouter(confidence_threshold=settings.intent_confidence_threshold)

    def _chat(
        self,
        messages,
        *,
        call_type="",
        session_id=None,
        temperature=0.7,
        max_tokens=1200,
        response_format=None,
        thinking=None,
        reasoning_effort=None,
    ):
        """包装 LLM 调用，自动设置 Prompt 追踪上下文"""
        if hasattr(self.llm, "set_context"):
            self.llm.set_context(call_type=call_type, session_id=session_id)
        return self.llm.chat(
            messages,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format=response_format,
            thinking=thinking,
            reasoning_effort=reasoning_effort,
        )

    def start_session(self) -> str:
        session_id = self.store.create_session()
        self.logger.info("session start id=%s", session_id)
        return session_id

    def generate_home_hint(self) -> dict:
        journals = self.store.list_journals(limit=5)
        profiles = self.store.list_state_profiles(limit=6)
        memories = self.store.list_memories(limit=8)
        liked_hints = self.store.list_home_hint_feedback(liked=True, limit=8)
        disliked_hints = self.store.list_home_hint_feedback(liked=False, limit=5)
        context = {
            "journal_ids": [item["id"] for item in journals[:3] if item.get("id")],
            "profile_ids": [item["id"] for item in profiles[:3] if item.get("id")],
            "memory_ids": [item["id"] for item in memories[:5] if item.get("id")],
        }
        
        # 从 home_hint.md 加载 prompt
        prompt = read_prompt("home_hint.md")
        user_context = (
            "最近日记：\n"
            f"{preview_text(json.dumps(journals, ensure_ascii=False), 2200)}\n\n"
            "长期状态画像：\n"
            f"{preview_text(render_state_profiles(profiles), 1600)}\n\n"
            "相关记忆：\n"
            f"{preview_text(render_memories(memories), 1800)}\n\n"
            "用户喜欢过的首页句子：\n"
            f"{preview_text(json.dumps([item.get('text', '') for item in liked_hints], ensure_ascii=False), 900)}\n\n"
            "用户取消喜欢或未偏好的首页句子：\n"
            f"{preview_text(json.dumps([item.get('text', '') for item in disliked_hints], ensure_ascii=False), 600)}"
        )
        try:
            response = self._chat(
                [
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": user_context},
                ],
                call_type="home_hint",
                temperature=0.7,
                max_tokens=120,
            )
            text = self._clean_home_hint_text(response.content)
            if text:
                return {
                    "id": str(uuid.uuid4()),
                    "text": text,
                    "source": "llm",
                    "liked": False,
                    "context": context,
                }
        except Exception:
            self.logger.exception("home hint generation failed")
        return self._fallback_home_hint(journals, profiles, context)

    def record_home_hint_feedback(
        self,
        *,
        hint_id: str,
        text: str,
        liked: bool,
        source: str = "",
        context: dict | None = None,
    ) -> None:
        self.store.record_home_hint_feedback(
            hint_id=hint_id,
            text=text,
            liked=liked,
            source=source,
            context=context,
        )

    def _fallback_home_hint(
        self,
        journals: list[dict],
        profiles: list[dict],
        context: dict,
    ) -> dict:
        latest_journal = journals[0] if journals else {}
        latest_profile = profiles[0] if profiles else {}
        emotion = latest_journal.get("dominant_emotion") or ""
        next_step = latest_journal.get("suggested_next_step") or ""
        state_summary = latest_profile.get("summary") or ""
        if emotion and next_step:
            text = f"我看见最近的{emotion}了，今晚只靠近一小步就好。"
        elif state_summary:
            text = "你正在经历的事情已经被看见，先让自己慢慢落回这里。"
        else:
            text = "你已经走到这里了，今晚可以先轻轻放下一点。"
        return {
            "id": str(uuid.uuid4()),
            "text": text,
            "source": "fallback",
            "liked": False,
            "context": context,
        }

    def generate_weekly_flow_insight(self) -> dict:
        now = datetime.now(timezone.utc)
        recent_journals = self.store.list_journals(limit=80)
        recent_messages = self.store.list_messages(limit=300)
        state_profiles = self.store.list_state_profiles(limit=8)
        memories = [
            item
            for item in self.store.list_memories(limit=80)
            if item.get("status") == "active"
        ]
        memories.sort(
            key=lambda item: (
                str(item.get("updated_at", "")),
                int(item.get("importance") or 0),
            ),
            reverse=True,
        )

        month_cutoff = now - timedelta(days=30)
        two_month_cutoff = now - timedelta(days=60)
        journals_30 = self._filter_items_since(recent_journals, "created_at", month_cutoff)
        messages_30 = self._filter_items_since(recent_messages, "created_at", month_cutoff)

        if len(journals_30) >= 2 or len(messages_30) >= 16:
            period_start = month_cutoff
            selected_journals = journals_30
            selected_messages = messages_30
        else:
            period_start = two_month_cutoff
            selected_journals = self._filter_items_since(recent_journals, "created_at", two_month_cutoff)
            selected_messages = self._filter_items_since(recent_messages, "created_at", two_month_cutoff)

        # Active memories are cross-session knowledge. Keep relevant older memories
        # available instead of limiting them to the journal review window.
        selected_memories = memories[:40]
        fallback = self._fallback_weekly_flow_insight(
            period_start=period_start,
            period_end=now,
            journals=selected_journals,
            messages=selected_messages,
            profiles=state_profiles,
            memories=selected_memories,
        )
        context = {
            "period_start": period_start.isoformat(),
            "period_end": now.isoformat(),
            "journal_count": len(selected_journals),
            "message_count": len(selected_messages),
            "journals": [
                {
                    "created_at": item.get("created_at", ""),
                    "summary": item.get("summary", ""),
                    "dominant_emotion": item.get("dominant_emotion", ""),
                    "keywords": item.get("keywords", []),
                    "insights": item.get("insights", []),
                    "suggested_next_step": item.get("suggested_next_step", ""),
                }
                for item in selected_journals[:12]
            ],
            "state_profiles": [
                {
                    "domain": item.get("domain", ""),
                    "stage": item.get("stage", ""),
                    "summary": item.get("summary", ""),
                    "trend": item.get("trend", ""),
                    "support_strategy": item.get("support_strategy", ""),
                }
                for item in state_profiles[:8]
            ],
            "memories": [
                {
                    "category": item.get("category", ""),
                    "subcategory": item.get("subcategory", ""),
                    "content": item.get("content", ""),
                    "evidence": item.get("evidence", ""),
                    "keywords": item.get("keywords", []),
                    "importance": item.get("importance", 0),
                    "updated_at": item.get("updated_at", ""),
                }
                for item in selected_memories[:30]
            ],
            "message_snippets": [
                {
                    "created_at": item.get("created_at", ""),
                    "role": item.get("role", ""),
                    "content": str(item.get("content", ""))[:120],
                }
                for item in selected_messages[-24:]
            ],
        }

        try:
            response = self._chat(
                [
                    {"role": "system", "content": read_prompt("weekly_flow_insight.md")},
                    {"role": "user", "content": json.dumps(context, ensure_ascii=False)},
                ],
                call_type="weekly_flow_insight",
                temperature=0.3,
                max_tokens=1200,
                response_format={"type": "json_object"},
            )
            payload = json.loads(response.content)
            if isinstance(payload, dict):
                normalized = self._normalize_weekly_flow_payload(payload, fallback=fallback)
                fallback.update(normalized)
        except Exception:
            self.logger.exception("star map monthly review failed")

        fallback["id"] = str(uuid.uuid4())
        fallback["generated_at"] = now.isoformat()
        fallback["period_start"] = period_start.isoformat()
        fallback["period_end"] = now.isoformat()
        return fallback

    @staticmethod
    def _clean_home_hint_text(text: str) -> str:
        cleaned = text.strip().strip("「」“”\"'")
        for prefix in ("文案：", "一句话：", "首页句子："):
            if cleaned.startswith(prefix):
                cleaned = cleaned.removeprefix(prefix).strip()
        lines = [line.strip() for line in cleaned.splitlines() if line.strip()]
        if lines:
            cleaned = lines[0]
        if len(cleaned) > 58:
            cleaned = cleaned[:58].rstrip("，。,. ") + "。"
        return cleaned

    def _normalize_weekly_flow_payload(self, payload: dict, fallback: dict) -> dict:
        def short_text(key: str, limit: int) -> str:
            text = str(payload.get(key) or fallback.get(key, "")).strip()
            return text[:limit]

        def string_list(key: str) -> list[str]:
            values = payload.get(key)
            if not isinstance(values, list):
                values = fallback.get(key, [])
            result = [str(item).strip()[:28] for item in values if str(item).strip()]
            return result[:4] or list(fallback.get(key, []))[:4]

        return {
            "primary_goal_title": short_text("primary_goal_title", 40),
            "primary_goal_reason": short_text("primary_goal_reason", 180),
            "primary_goal_next_step": short_text("primary_goal_next_step", 100),
            "primary_goal_challenge": self._normalize_flow_challenge(
                payload.get("primary_goal_challenge"),
                fallback.get("primary_goal_challenge", "轻量"),
            ),
            "secondary_goal_title": short_text("secondary_goal_title", 40),
            "secondary_goal_reason": short_text("secondary_goal_reason", 180),
            "secondary_goal_next_step": short_text("secondary_goal_next_step", 100),
            "secondary_goal_challenge": self._normalize_flow_challenge(
                payload.get("secondary_goal_challenge"),
                fallback.get("secondary_goal_challenge", ""),
                allow_empty=True,
            ),
            "recent_emotion_summary": short_text("recent_emotion_summary", 220),
            "recent_emotion_tags": string_list("recent_emotion_tags"),
            "flow_support": short_text("flow_support", 220),
            "memory_cues": self._normalize_flow_memory_cues(
                payload.get("memory_cues"),
                fallback.get("memory_cues", []),
            ),
            "core_insight": short_text("core_insight", 120),
            "core_insight_detail": short_text("core_insight_detail", 240),
            "recent_pattern_title": short_text("recent_pattern_title", 20),
            "recent_pattern_items": string_list("recent_pattern_items"),
            "recent_pattern_detail": short_text("recent_pattern_detail", 240),
            "flow_condition_title": short_text("flow_condition_title", 24),
            "flow_condition_items": string_list("flow_condition_items"),
            "flow_condition_detail": short_text("flow_condition_detail", 240),
            "gentle_reminder_title": short_text("gentle_reminder_title", 20),
            "gentle_reminder": short_text("gentle_reminder", 120),
            "gentle_reminder_detail": short_text("gentle_reminder_detail", 240),
            "source_summary": short_text("source_summary", 160),
        }

    @staticmethod
    def _normalize_flow_challenge(
        value: object,
        fallback: str,
        *,
        allow_empty: bool = False,
    ) -> str:
        text = str(value or "").strip()
        if allow_empty and not text:
            return ""
        return text if text in {"轻量", "适中", "稍有挑战"} else fallback

    @staticmethod
    def _normalize_flow_memory_cues(value: object, fallback: list[str]) -> list[str]:
        values = value if isinstance(value, list) else fallback
        result = [str(item).strip()[:120] for item in values if str(item).strip()]
        return result[:4] or fallback[:4]

    def _fallback_weekly_flow_insight(
        self,
        *,
        period_start: datetime,
        period_end: datetime,
        journals: list[dict],
        messages: list[dict],
        profiles: list[dict],
        memories: list[dict],
    ) -> dict:
        keywords: list[str] = []
        for journal in journals[:8]:
            for keyword in journal.get("keywords", [])[:4]:
                text = str(keyword).strip()
                if text and text not in keywords:
                    keywords.append(text)
        if not keywords:
            keywords = [str(item.get("subcategory", "")).strip() for item in memories[:3] if str(item.get("subcategory", "")).strip()]
        if not keywords:
            keywords = ["独处", "慢一点", "被看见"]

        recent_summary = str(journals[0].get("summary", "")).strip() if journals else ""
        profile_summary = str(profiles[0].get("summary", "")).strip() if profiles else ""
        evidence_text = "；".join(part for part in [recent_summary[:48], profile_summary[:48]] if part)
        if not evidence_text:
            evidence_text = "最近的材料还不算多，所以这份观察先保持在比较保守的程度。"

        pattern_items = keywords[1:4] if len(keywords) > 1 else keywords[:3]
        if not pattern_items:
            pattern_items = ["先感受", "再整理", "慢慢说"]

        recent_emotions = []
        for journal in journals[:6]:
            emotion = str(journal.get("dominant_emotion", "")).strip()
            if emotion and emotion not in recent_emotions:
                recent_emotions.append(emotion)

        primary_memory = memories[0] if memories else {}
        primary_memory_text = str(primary_memory.get("content", "")).strip()
        primary_keyword = (
            str(primary_memory.get("subcategory", "")).strip()
            or (keywords[0] if keywords else "真实感受")
        )
        profile_strategy = str(profiles[0].get("support_strategy", "")).strip() if profiles else ""
        challenge = "轻量" if any(
            emotion in {"疲惫", "焦虑", "难过", "无力", "压抑", "混乱"}
            for emotion in recent_emotions
        ) else "适中"

        memory_cues = []
        for memory in memories[:4]:
            content = str(memory.get("content", "")).strip()
            if content:
                memory_cues.append(f"记录里曾留下：{content[:96]}")
        if not memory_cues:
            memory_cues = ["目前可用的长期记忆还不多，可以先从最近反复出现的兴趣或牵挂开始。"]

        return {
            "primary_goal_title": f"靠近「{primary_keyword}」里最重要的一小步",
            "primary_goal_reason": (
                f"最近的记录反复指向这个方向。{primary_memory_text[:90]}"
                if primary_memory_text
                else "目前资料还不多，先把目标放在能被感受到、也能轻轻开始的一小步上。"
            ),
            "primary_goal_next_step": "选一个十几分钟内可以开始的动作，只做到能继续的位置。",
            "primary_goal_challenge": challenge,
            "secondary_goal_title": "",
            "secondary_goal_reason": "",
            "secondary_goal_next_step": "",
            "secondary_goal_challenge": "",
            "recent_emotion_summary": (
                f"最近较常出现的情绪是{'、'.join(recent_emotions[:3])}。"
                "这些感受可能会让注意力更容易分散，所以目标需要更小、更清楚，也允许中途停下。"
                if recent_emotions
                else "近期情绪记录还不够完整，暂时更适合用低压力的小目标观察自己的专注和能量。"
            ),
            "recent_emotion_tags": recent_emotions[:4] or ["待观察"],
            "flow_support": profile_strategy or "先收窄到一件具体的事，移开结果压力，为开始动作留出清楚的边界。",
            "memory_cues": memory_cues,
            "core_insight": "这段时间里，\n你比较有生命力的时刻，\n常出现在能慢慢靠近真实感受的时候。",
            "core_insight_detail": f"从最近的总结和对话看，当你不急着把自己定性，而是允许自己先感受、再整理时，内在会更容易松开一点。{evidence_text}",
            "recent_pattern_title": "最近的模式",
            "recent_pattern_items": pattern_items[:3],
            "recent_pattern_detail": "最近你似乎在重复一种节奏：先察觉到不舒服，再试着给它命名，最后才慢慢找到能落地的一小步。这说明你不是停住了，而是在形成自己的整理方式。",
            "flow_condition_title": "容易进入星流的时候",
            "flow_condition_items": keywords[:3],
            "flow_condition_detail": "从现有材料看，当外界催促稍微少一点、你能保留一点独处或自由整理的空间时，思路会更容易连起来，也更容易感到自己是活着的、在流动的。",
            "gentle_reminder_title": "一个温柔提醒",
            "gentle_reminder": "如果最近又开始急着\n解释自己，也可以先\n把感受留在身边。",
            "gentle_reminder_detail": "最近的状态不一定需要立刻变成结论。有时候先把感受留在旁边，让它被看见、被陪一会儿，反而会比快速分析更有帮助。",
            "source_summary": f"基于 {period_start.date().isoformat()} 到 {period_end.date().isoformat()} 的夜谈、总结、状态画像与记忆整理。",
        }

    def _filter_items_since(
        self,
        items: list[dict],
        date_key: str,
        cutoff: datetime,
    ) -> list[dict]:
        result = []
        for item in items:
            raw_value = str(item.get(date_key, "")).strip()
            if not raw_value:
                continue
            try:
                created_at = datetime.fromisoformat(raw_value.replace("Z", "+00:00"))
            except ValueError:
                continue
            if created_at >= cutoff:
                result.append(item)
        return result

    def reply(self, session_id: str, user_text: str, character_id: str | None = None) -> str:
        return self.reply_detail(session_id, user_text, character_id=character_id)["reply"]

    def reply_detail(
        self,
        session_id: str,
        user_text: str,
        character_id: str | None = None,
    ) -> dict:
        started_at = time.monotonic()
        debug_trace = {
            "mode": "rabbit_auto" if character_id == "auto" else "manual_rabbit_form",
            "steps": [],
            "llm_calls": [],
        }
        state_profiles = self.store.list_state_profiles()

        self.store.add_message(session_id, "user", user_text)
        self.logger.info("reply start session=%s character=%s user_chars=%s", session_id, character_id, len(user_text))

        # 危机检测保持在模型调用之前，但用户输入要先保存，便于历史和安全复盘。
        if detect_crisis(user_text):
            if character_id == "auto":
                character = auto_select_character(user_text)
            else:
                character = get_character(character_id)
            return self._crisis_response(
                session_id, user_text, character.id, debug_trace, started_at,
            )

        if character_id == "auto":
            messages = self.store.get_session_messages(session_id)
            recent_history = messages[-(5 * 2):]  # 最近 5 轮

            # 统一意图识别
            intent_result = self.intent_agent.recognize(user_text, recent_history)
            debug_trace["steps"].append({
                "name": "intent_recognition",
                "status": "done",
                "summary": f"意图={intent_result.intent} 置信度={intent_result.confidence:.2f} 风险={intent_result.risk_level}",
                "output": {
                    "intent": intent_result.intent,
                    "confidence": intent_result.confidence,
                    "emotion": intent_result.emotion,
                    "risk_level": intent_result.risk_level,
                    "user_state": intent_result.user_state,
                    "core_need": intent_result.core_need,
                    "response_mode": intent_result.response_mode,
                    "memory_queries": intent_result.memory_queries,
                    "knowledge_queries": intent_result.knowledge_queries,
                    "reason": intent_result.reason,
                },
            })

            # 路由决策
            reply_path = self.intent_router.decide(intent_result, user_text)
            debug_trace["steps"].append({
                "name": "intent_routing",
                "status": "done",
                "summary": f"路由路径={reply_path.path} use_thinking={reply_path.use_thinking}",
            })

            # 按路径分流
            if reply_path.path == "crisis":
                character = get_character(reply_path.route_plan["character_id"]) if reply_path.route_plan else auto_select_character(user_text)
                return self._crisis_response(session_id, user_text, character.id, debug_trace, started_at)
            elif reply_path.path == "quick":
                return self._quick_response(session_id, user_text, reply_path, messages, debug_trace, started_at)
            elif reply_path.path == "clarify":
                return self._clarify_response(session_id, user_text, reply_path, debug_trace, started_at)
            elif reply_path.path == "interaction":
                return self._interaction_response(session_id, user_text, reply_path, debug_trace, started_at)
            elif reply_path.path == "deep":
                if reply_path.use_thinking:
                    # 低置信度：回退到 thinking 模式的策略规划
                    route_plan = self._choose_reply_roles(
                        session_id, user_text,
                        state_profiles=state_profiles,
                        debug_trace=debug_trace,
                    )
                else:
                    route_plan = reply_path.route_plan
                return self._deep_response(
                    session_id, user_text, route_plan,
                    messages, state_profiles, debug_trace, started_at,
                )
            else:
                # 未知路径回退到 deep
                route_plan = self._choose_reply_roles(
                    session_id, user_text,
                    state_profiles=state_profiles,
                    debug_trace=debug_trace,
                )
                return self._deep_response(
                    session_id, user_text, route_plan,
                    messages, state_profiles, debug_trace, started_at,
                )
        else:
            # 手动角色模式：保持原有逻辑
            character = get_character(character_id)
            route_plan = None
            debug_trace["manual_character_id"] = character.id
            debug_trace["steps"].append({
                "name": "manual_character",
                "status": "done",
                "summary": f"使用手动选择角色：{character.name}。",
            })
            messages = self.store.get_session_messages(session_id)
            return self._deep_response(
                session_id, user_text, route_plan,
                messages, state_profiles, debug_trace, started_at,
            )

    # ------------------------------------------------------------------
    # 多路径响应方法
    # ------------------------------------------------------------------

    def _crisis_response(
        self,
        session_id: str,
        user_text: str,
        character_id: str,
        debug_trace: dict,
        started_at: float,
    ) -> dict:
        """危机干预响应路径。"""
        character = get_character(character_id)
        expression_id = normalize_expression_id(character.id, "concerned")
        self.store.add_message(
            session_id,
            "assistant",
            CRISIS_RESPONSE,
            model="safety",
            metadata={"character_id": character.id, "expression_id": expression_id},
        )
        self.logger.info("reply safety session=%s", session_id)
        return {
            "reply": CRISIS_RESPONSE,
            "knowledge_cards": [],
            "character": character.to_public_dict(),
            "expression": {
                "id": expression_id,
                **((character.expressions or {}).get(expression_id, {})),
            },
            "route_plan": None,
            "debug_trace": {
                **debug_trace,
                "steps": debug_trace["steps"] + [{
                    "name": "safety",
                    "status": "triggered",
                    "summary": "命中安全兜底回复，未继续调用生成模型。",
                }],
                "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                "llm_call_count": len(debug_trace["llm_calls"]),
            },
        }

    def _deep_response(
        self,
        session_id: str,
        user_text: str,
        route_plan: dict | None,
        messages: list,
        state_profiles: list[dict],
        debug_trace: dict,
        started_at: float,
        extra_metadata: dict | None = None,
        quick_reply_text: str | None = None,
    ) -> dict:
        """深度回复路径（含兔子形态结构化回复和手动角色回复）。"""
        if route_plan:
            character = get_character(route_plan["character_id"])
            debug_trace["steps"].append({
                "name": "turn_planner",
                "status": "done",
                "summary": "已完成本轮状态、需求、回复模式、兔子形态与表情规划。",
                "output": route_plan,
            })
        else:
            character = get_character(
                debug_trace.get("manual_character_id", "mianmian"),
            )

        memory_queries = route_plan.get("memory_queries", []) if route_plan else []
        knowledge_queries = []
        if route_plan:
            knowledge_queries = route_plan.get("knowledge_needs", []) + route_plan.get("knowledge_queries", [])
        
        need_more_memories = route_plan.get("need_more_memories", False) if route_plan else False
        relevant_limit = 10 if need_more_memories else 5
        total_limit = 20 if need_more_memories else 10
        
        memories = self.store.search_memories_hybrid(
            user_text,
            query_terms=memory_queries,
            relevant_limit=relevant_limit,
            recent_limit=1,
            important_limit=2,
            important_threshold=5,
            total_limit=total_limit,
        )
        memory_keywords = []
        for memory in memories:
            keywords = memory["keywords"]
            if isinstance(keywords, str):
                try:
                    keywords = json.loads(keywords)
                except json.JSONDecodeError:
                    keywords = []
            memory_keywords.extend(keywords)
        knowledge_plan = self.knowledge.retrieve_plan(
            user_text,
            memory_keywords=[] if route_plan else memory_keywords,
            query_terms=knowledge_queries,
            limit=3,
        )
        knowledge_cards = knowledge_plan["primary_cards"]
        public_knowledge_plan = {
            **knowledge_plan,
            "primary_cards": [
                {
                    "id": card.get("id", ""),
                    "title": card.get("title", ""),
                    "concept_type": card.get("concept_type", ""),
                    "source_ref": card.get("source_ref", ""),
                }
                for card in knowledge_cards
            ],
        }
        debug_trace["steps"].append({
            "name": "retrieve_context",
            "status": "done",
            "summary": "已读取历史消息、长期记忆，并检索知识卡。",
            "output": {
                "history_messages": max(0, len(messages) - 1),
                "memory_count": len(memories),
                "memory_queries": memory_queries,
                "state_profile_count": len(state_profiles),
                "knowledge_queries": knowledge_queries,
                "retrieved_memories": [
                    {
                        "category": memory.get("category", ""),
                        "subcategory": memory.get("subcategory", ""),
                        "content": memory.get("content", ""),
                    }
                    for memory in memories[:8]
                ],
                "knowledge_cards": [card.get("title", "") for card in knowledge_cards],
                "knowledge_plan": public_knowledge_plan,
            },
        })
        history_turns_needed = route_plan.get("history_turns_needed", 5) if route_plan else 5
        need_state_profiles = route_plan.get("need_state_profiles", True) if route_plan else True
        
        history_messages = messages[:-1]
        if history_turns_needed > 0:
            history_messages = history_messages[-history_turns_needed * 2:]
        else:
            history_messages = []
        
        conversation_history_section = f"当前对话历史：\n{render_conversation_history(history_messages)}"
        
        state_profiles_text = render_state_profiles(state_profiles) if need_state_profiles else "当前不需要长期状态画像。"
        
        system_prompt = read_prompt("persona.md").format(
            character_profile=character.prompt,
            current_character_name=character.name,
            character_tagline=character.tagline,
            character_voice=character.voice,
            conversation_history_section=conversation_history_section,
            memories=render_memories(memories),
            state_profiles=state_profiles_text,
            knowledge_cards=render_knowledge_cards(knowledge_cards, knowledge_plan),
            role_plan=render_role_plan(route_plan),
            rabbit_response_instruction=render_rabbit_response_instruction(route_plan) if route_plan else "",
            quick_reply_handoff=render_quick_reply_handoff(quick_reply_text),
        )
        if quick_reply_text:
            debug_trace["steps"].append({
                "name": "quick_reply_handoff",
                "status": "done",
                "summary": "深度回复已读取先前显示的即时回应，并被要求只补充新增价值。",
                "output": {"quick_reply_chars": len(quick_reply_text)},
            })
        llm_messages = [{"role": "system", "content": system_prompt}]
        llm_messages.append({"role": "user", "content": user_text})

        generation_started_at = time.monotonic()
        try:
            response = self._chat(
                llm_messages,
                call_type="reply",
                session_id=session_id,
                temperature=0.75,
                max_tokens=2000,
                response_format={"type": "json_object"} if route_plan else None,
                thinking="disabled",
            )
        except Exception as error:
            self.logger.exception(
                "deep reply generation failed session=%s error=%s",
                session_id,
                error,
            )
            reply_content = (
                "我暂时没能好好回应你。你可以稍后再试一次；"
                "如果愿意，也可以先把此刻最难受的一点留在这里。"
            )
            expression_id = normalize_expression_id(character.id, None)
            debug_trace["steps"].append({
                "name": "generate_reply",
                "status": "fallback",
                "summary": "回复模型调用失败，已返回本地降级提示。",
            })
            self.store.add_message(
                session_id,
                "assistant",
                reply_content,
                model="fallback",
                metadata={
                    "character_id": character.id,
                    "expression_id": expression_id,
                    "route_plan": route_plan,
                    "generation_error": type(error).__name__,
                    **(extra_metadata or {}),
                },
            )
            return {
                "reply": reply_content,
                "group_messages": [],
                "knowledge_cards": knowledge_cards,
                "knowledge_plan": public_knowledge_plan,
                "retrieved_memories": [
                    {
                        "id": memory.get("id", ""),
                        "category": memory.get("category", ""),
                        "subcategory": memory.get("subcategory", ""),
                        "content": memory.get("content", ""),
                        "evidence": memory.get("evidence", ""),
                        "keywords": memory.get("keywords", []),
                    }
                    for memory in memories[:8]
                ],
                "character": character.to_public_dict(),
                "expression": {
                    "id": expression_id,
                    **((character.expressions or {}).get(expression_id, {})),
                },
                "route_plan": route_plan,
                "debug_trace": {
                    **debug_trace,
                    "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                    "llm_call_count": len(debug_trace["llm_calls"]),
                },
            }
        generation_call = {
            "name": "rabbit_response" if route_plan else "single_reply",
            "model": response.model,
            "elapsed_sec": round(time.monotonic() - generation_started_at, 2),
            "response_format": "json_object" if route_plan else "text",
            "raw_output": preview_text(response.content),
        }
        reply_content = response.content
        expression_id = character.default_expression_id
        if route_plan:
            try:
                payload = json.loads(response.content)
                reply_content = str(payload.get("reply") or "").strip() or response.content
                expression_id = normalize_expression_id(character.id, payload.get("expression_id") or route_plan.get("expression_id"))
                generation_call["parsed_output"] = {
                    "reply": preview_text(reply_content),
                    "expression_id": expression_id,
                }
            except (TypeError, json.JSONDecodeError):
                expression_id = normalize_expression_id(character.id, route_plan.get("expression_id"))
                self.logger.exception("rabbit response parse failed; falling back to raw reply")
                generation_call["parse_error"] = "JSON 解析失败，已回退为原始文本。"
        else:
            expression_id = normalize_expression_id(character.id, None)
        debug_trace["llm_calls"].append(generation_call)
        debug_trace["steps"].append({
            "name": "generate_reply",
            "status": "done",
            "summary": "已生成回复内容。" if not route_plan else "已生成兔子形态结构化回复。",
            "output": {
                "main_character": character.name,
                "expression_id": expression_id,
                "reply_chars": len(reply_content),
            },
        })
        self.store.add_message(
            session_id,
            "assistant",
            reply_content,
            model=response.model,
            metadata={
                "character_id": character.id,
                "expression_id": expression_id,
                "route_plan": route_plan,
                "knowledge_card_ids": [card.get("id", "") for card in knowledge_cards if card.get("id")],
                **(extra_metadata or {}),
            },
        )
        self.logger.info(
            "reply done session=%s elapsed=%.2fs model=%s reply_chars=%s",
            session_id,
            time.monotonic() - started_at,
            response.model,
            len(reply_content),
        )
        return {
            "reply": reply_content,
            "group_messages": [],
            "knowledge_cards": knowledge_cards,
            "knowledge_plan": public_knowledge_plan,
            "retrieved_memories": [
                {
                    "id": memory.get("id", ""),
                    "category": memory.get("category", ""),
                    "subcategory": memory.get("subcategory", ""),
                    "content": memory.get("content", ""),
                    "evidence": memory.get("evidence", ""),
                    "keywords": memory.get("keywords", []),
                }
                for memory in memories[:8]
            ],
            "character": character.to_public_dict(),
            "expression": {
                "id": expression_id,
                **((character.expressions or {}).get(expression_id, {})),
            },
            "route_plan": route_plan,
            "debug_trace": {
                **debug_trace,
                "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                "llm_call_count": len(debug_trace["llm_calls"]),
            },
        }

    def _quick_response(
        self,
        session_id: str,
        user_text: str,
        reply_path,
        messages: list,
        debug_trace: dict,
        started_at: float,
    ) -> dict:
        """轻量快速回复路径。使用短上下文、简化 persona、max_tokens=400。"""
        route_plan = reply_path.route_plan
        character_id = route_plan["character_id"] if route_plan else auto_select_character(user_text).id
        character = get_character(character_id)
        short_messages = messages[-10:]

        quick_text = self._generate_quick_reply_text(
            user_text,
            short_messages,
            character_id,
            debug_trace=debug_trace,
        )
        expression_id = normalize_expression_id(character.id, route_plan.get("expression_id") if route_plan else None)

        self.store.add_message(
            session_id,
            "assistant",
            quick_text,
            model="quick",
            metadata={
                "character_id": character.id,
                "expression_id": expression_id,
                "route_plan": route_plan,
                "reply_path": "quick",
            },
        )
        self.logger.info("quick reply done session=%s elapsed=%.2fs", session_id, time.monotonic() - started_at)

        return {
            "reply": quick_text,
            "group_messages": [],
            "knowledge_cards": [],
            "character": character.to_public_dict(),
            "expression": {
                "id": expression_id,
                **((character.expressions or {}).get(expression_id, {})),
            },
            "route_plan": route_plan,
            "debug_trace": {
                **debug_trace,
                "steps": debug_trace["steps"] + [{
                    "name": "quick_reply",
                    "status": "done",
                    "summary": "已通过轻量路径生成快速回复。",
                }],
                "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                "llm_call_count": len(debug_trace["llm_calls"]),
            },
        }

    def _clarify_response(
        self,
        session_id: str,
        user_text: str,
        reply_path,
        debug_trace: dict,
        started_at: float,
    ) -> dict:
        """追问路径。直接使用 intent 阶段已生成的 clarify_reply，不调用 LLM。"""
        route_plan = reply_path.route_plan
        clarify_text = reply_path.intent_result.clarify_reply or "你能再说多一点吗？我想更好地理解你现在的感受。"

        character_id = route_plan["character_id"] if route_plan else auto_select_character(user_text).id
        character = get_character(character_id)
        expression_id = normalize_expression_id(character.id, route_plan.get("expression_id") if route_plan else None)

        self.store.add_message(
            session_id,
            "assistant",
            clarify_text,
            model="clarify",
            metadata={
                "character_id": character.id,
                "expression_id": expression_id,
                "route_plan": route_plan,
                "reply_path": "clarify",
            },
        )
        self.logger.info("clarify reply done session=%s elapsed=%.2fs", session_id, time.monotonic() - started_at)

        return {
            "reply": clarify_text,
            "group_messages": [],
            "knowledge_cards": [],
            "character": character.to_public_dict(),
            "expression": {
                "id": expression_id,
                **((character.expressions or {}).get(expression_id, {})),
            },
            "route_plan": route_plan,
            "debug_trace": {
                **debug_trace,
                "steps": debug_trace["steps"] + [{
                    "name": "clarify_reply",
                    "status": "done",
                    "summary": "已通过追问路径返回 clarify_reply，未调用 LLM。",
                }],
                "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                "llm_call_count": len(debug_trace.get("llm_calls", [])),
            },
        }

    def _interaction_response(
        self,
        session_id: str,
        user_text: str,
        reply_path,
        debug_trace: dict,
        started_at: float,
    ) -> dict:
        """交互引导路径（呼吸练习、身体扫描等），使用模板生成。"""
        route_plan = reply_path.route_plan
        interaction_type = reply_path.intent_result.interaction_type or "breathing"

        character_id = route_plan["character_id"] if route_plan else auto_select_character(user_text).id
        character = get_character(character_id)
        expression_id = normalize_expression_id(character.id, route_plan.get("expression_id") if route_plan else None)

        interaction_text = self._generate_interaction_content(interaction_type, character)

        self.store.add_message(
            session_id,
            "assistant",
            interaction_text,
            model="interaction",
            metadata={
                "character_id": character.id,
                "expression_id": expression_id,
                "route_plan": route_plan,
                "reply_path": "interaction",
                "interaction_type": interaction_type,
            },
        )
        self.logger.info("interaction reply done session=%s type=%s elapsed=%.2fs", session_id, interaction_type, time.monotonic() - started_at)

        return {
            "reply": interaction_text,
            "group_messages": [],
            "knowledge_cards": [],
            "character": character.to_public_dict(),
            "expression": {
                "id": expression_id,
                **((character.expressions or {}).get(expression_id, {})),
            },
            "route_plan": route_plan,
            "debug_trace": {
                **debug_trace,
                "steps": debug_trace["steps"] + [{
                    "name": "interaction_reply",
                    "status": "done",
                    "summary": f"已通过交互路径生成 {interaction_type} 引导内容。",
                }],
                "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                "llm_call_count": len(debug_trace.get("llm_calls", [])),
            },
        }

    def reply_stream(
        self,
        session_id: str,
        user_text: str,
        character_id: str = "auto",
    ):
        """SSE 流式推送生成器。并行执行意图识别 + 快速回复生成，推送事件。"""
        started_at = time.monotonic()
        debug_trace = {
            "mode": "rabbit_auto" if character_id == "auto" else "manual_rabbit_form",
            "steps": [],
            "llm_calls": [],
        }

        self.store.add_message(session_id, "user", user_text)

        # 危机检测
        if detect_crisis(user_text):
            character_id_resolved = character_id if character_id != "auto" else auto_select_character(user_text).id
            result = self._crisis_response(session_id, user_text, character_id_resolved, debug_trace, started_at)
            yield self._sse_event("final", result)
            yield self._sse_event("done", result)
            return

        messages = self.store.get_session_messages(session_id)
        state_profiles = self.store.list_state_profiles()

        # 先并行执行：意图识别 + 快速回复生成
        quick_text = ""
        quick_character_id = character_id if character_id != "auto" else auto_select_character(user_text).id
        quick_character = get_character(quick_character_id)
        quick_expression_id = normalize_expression_id(quick_character.id, None)
        reply_group_id = str(uuid.uuid4())

        executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="reply-stream")
        intent_future = None
        try:
            if character_id == "auto":
                intent_future = executor.submit(
                    self.intent_agent.recognize, user_text, messages[-(5 * 2):],
                )

            quick_future = executor.submit(
                self._generate_quick_reply_text,
                user_text,
                messages,
                quick_character_id,
                debug_trace=debug_trace,
            )

            # 等待真实 quick 模型结果。quick 的速度通过更短 prompt / 更少上下文 / 更小 max_tokens 控制，
            # 不使用本地模板兜底，避免前端展示内容与开发面板 trace 不一致。
            quick_source = "llm"
            quick_reply_payload = None
            try:
                quick_text = quick_future.result()
            except Exception:
                self.logger.exception("quick reply generation failed in stream mode; skip quick event")
                debug_trace["steps"].append({
                    "name": "quick_reply",
                    "status": "skipped",
                    "summary": "快速回复模型调用失败，未使用本地模板兜底。",
                })
            if quick_text:
                quick_reply_payload = {
                    "text": quick_text,
                    "character": quick_character.to_public_dict(),
                    "expression": {"id": quick_expression_id, **((quick_character.expressions or {}).get(quick_expression_id, {}))},
                    "source": quick_source,
                }
                debug_trace["quick_reply"] = quick_reply_payload
                self.store.add_message(
                    session_id,
                    "assistant",
                    quick_text,
                    model="quick",
                    metadata={
                        "character_id": quick_character.id,
                        "expression_id": quick_expression_id,
                        "reply_path": "quick",
                        "reply_stage": "quick",
                        "reply_group_id": reply_group_id,
                        "quick_source": quick_source,
                    },
                )

                # 推送快速回复（第一次回复）
                yield self._sse_event("quick_reply", quick_reply_payload)

            # 等待意图识别结果
            reply_path = None
            intent_result = None
            if intent_future is not None:
                try:
                    intent_result = intent_future.result(timeout=8)
                    reply_path = self.intent_router.decide(intent_result, user_text)
                    debug_trace["steps"].append({
                        "name": "intent_recognition",
                        "status": "done",
                        "summary": f"意图={intent_result.intent} 置信度={intent_result.confidence:.2f} 风险={intent_result.risk_level}",
                        "output": {
                            "intent": intent_result.intent,
                            "confidence": intent_result.confidence,
                            "emotion": intent_result.emotion,
                            "risk_level": intent_result.risk_level,
                            "user_state": intent_result.user_state,
                            "core_need": intent_result.core_need,
                            "response_mode": intent_result.response_mode,
                            "memory_queries": intent_result.memory_queries,
                            "knowledge_queries": intent_result.knowledge_queries,
                            "reason": intent_result.reason,
                        },
                    })
                    debug_trace["steps"].append({
                        "name": "intent_routing",
                        "status": "done",
                        "summary": f"路由路径={reply_path.path} use_thinking={reply_path.use_thinking}",
                        "output": {
                            "path": reply_path.path,
                            "use_thinking": reply_path.use_thinking,
                            "route_plan": reply_path.route_plan,
                        },
                    })
                except Exception:
                    self.logger.exception("intent recognition failed in stream mode")

            # 根据路由结果决定第二次回复
            def attach_deep_reply(result: dict) -> None:
                debug_trace["deep_reply"] = result["deep_reply"]
                if isinstance(result.get("debug_trace"), dict):
                    if quick_reply_payload is not None:
                        result["debug_trace"]["quick_reply"] = quick_reply_payload
                    result["debug_trace"]["deep_reply"] = result["deep_reply"]

            if reply_path is None or character_id != "auto":
                route_plan = None
                if character_id == "auto":
                    route_plan = self._choose_reply_roles(
                        session_id, user_text,
                        state_profiles=state_profiles,
                        debug_trace=debug_trace,
                    )
                final_result = self._deep_response(
                    session_id, user_text, route_plan,
                    messages, state_profiles, debug_trace, started_at,
                    extra_metadata={"reply_stage": "deep", "reply_group_id": reply_group_id},
                    quick_reply_text=quick_text if quick_reply_payload is not None else None,
                )
                final_result["deep_reply"] = {
                    "text": final_result["reply"],
                    "character": final_result["character"],
                    "expression": final_result.get("expression", {}),
                }
                if quick_reply_payload is not None:
                    final_result["quick_reply"] = quick_reply_payload
                attach_deep_reply(final_result)
                yield self._sse_event("deep_reply", final_result)
                yield self._sse_event("final", final_result)
            elif reply_path.path == "deep":
                if reply_path.use_thinking:
                    route_plan = self._choose_reply_roles(
                        session_id, user_text,
                        state_profiles=state_profiles,
                        debug_trace=debug_trace,
                    )
                else:
                    route_plan = reply_path.route_plan
                final_result = self._deep_response(
                    session_id, user_text, route_plan,
                    messages, state_profiles, debug_trace, started_at,
                    extra_metadata={"reply_stage": "deep", "reply_group_id": reply_group_id},
                    quick_reply_text=quick_text if quick_reply_payload is not None else None,
                )
                final_result["deep_reply"] = {
                    "text": final_result["reply"],
                    "character": final_result["character"],
                    "expression": final_result.get("expression", {}),
                }
                if quick_reply_payload is not None:
                    final_result["quick_reply"] = quick_reply_payload
                attach_deep_reply(final_result)
                yield self._sse_event("deep_reply", final_result)
                yield self._sse_event("final", final_result)
            elif reply_path.path == "quick":
                if quick_reply_payload is None:
                    final_result = self._deep_response(
                        session_id, user_text, reply_path.route_plan,
                        messages, state_profiles, debug_trace, started_at,
                        extra_metadata={"reply_stage": "deep", "reply_group_id": reply_group_id},
                    )
                    final_result["deep_reply"] = {
                        "text": final_result["reply"],
                        "character": final_result["character"],
                        "expression": final_result.get("expression", {}),
                    }
                    attach_deep_reply(final_result)
                    yield self._sse_event("deep_reply", final_result)
                    yield self._sse_event("final", final_result)
                    yield self._sse_event("done", {"status": "complete"})
                    return
                final_result = {
                    "reply": quick_text,
                    "group_messages": [],
                    "knowledge_cards": [],
                    "character": quick_character.to_public_dict(),
                    "expression": quick_reply_payload["expression"],
                    "route_plan": reply_path.route_plan,
                    "quick_reply": quick_reply_payload,
                    "debug_trace": {
                        **debug_trace,
                        "steps": debug_trace["steps"] + [{
                            "name": "quick_reply_final",
                            "status": "done",
                            "summary": "快速回复即为最终回复，无第二次生成。",
                        }],
                        "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                        "llm_call_count": len(debug_trace["llm_calls"]),
                    },
                }
                yield self._sse_event("final", final_result)
            elif reply_path.path == "clarify":
                final_result = self._clarify_response(
                    session_id, user_text, reply_path, debug_trace, started_at,
                )
                if quick_reply_payload is not None:
                    final_result["quick_reply"] = quick_reply_payload
                final_result["deep_reply"] = {
                    "text": final_result["reply"],
                    "character": final_result["character"],
                    "expression": final_result.get("expression", {}),
                }
                attach_deep_reply(final_result)
                yield self._sse_event("deep_reply", final_result)
                yield self._sse_event("final", final_result)
            elif reply_path.path == "interaction":
                final_result = self._interaction_response(
                    session_id, user_text, reply_path, debug_trace, started_at,
                )
                if quick_reply_payload is not None:
                    final_result["quick_reply"] = quick_reply_payload
                final_result["deep_reply"] = {
                    "text": final_result["reply"],
                    "character": final_result["character"],
                    "expression": final_result.get("expression", {}),
                }
                attach_deep_reply(final_result)
                yield self._sse_event("deep_reply", final_result)
                yield self._sse_event("final", final_result)
            elif reply_path.path == "crisis":
                character = get_character(reply_path.route_plan["character_id"]) if reply_path.route_plan else auto_select_character(user_text)
                final_result = self._crisis_response(session_id, user_text, character.id, debug_trace, started_at)
                if quick_reply_payload is not None:
                    final_result["quick_reply"] = quick_reply_payload
                final_result["deep_reply"] = {
                    "text": final_result["reply"],
                    "character": final_result["character"],
                    "expression": final_result.get("expression", {}),
                }
                attach_deep_reply(final_result)
                yield self._sse_event("deep_reply", final_result)
                yield self._sse_event("final", final_result)

            yield self._sse_event("done", {"status": "complete"})
        finally:
            executor.shutdown(wait=False, cancel_futures=True)

    # ------------------------------------------------------------------
    # 辅助方法
    # ------------------------------------------------------------------

    def _generate_quick_reply_text(
        self,
        user_text: str,
        recent_history: list,
        character_id: str,
        debug_trace: dict | None = None,
    ) -> str:
        """使用极短上下文生成真实 quick 回复。"""
        character = get_character(character_id)
        system_prompt = read_prompt("quick_reply_py.md").format(
            last_user_message=user_text,
            current_character_name=character.name,
            character_tagline=character.tagline,
        )
        started_at = time.monotonic()
        response = self._chat(
            [{"role": "system", "content": system_prompt}, {"role": "user", "content": user_text}],
            call_type="quick_reply",
            temperature=0.65,
            max_tokens=self.quick_reply_max_tokens,
        )
        content = response.content.strip()
        
        try:
            payload = json.loads(content)
            if isinstance(payload, dict) and "text" in payload:
                content = str(payload["text"]).strip()
            elif isinstance(payload, dict) and "reply" in payload:
                content = str(payload["reply"]).strip()
        except (TypeError, json.JSONDecodeError):
            pass
        
        if debug_trace is not None:
            debug_trace["llm_calls"].append({
                "name": "quick_reply",
                "model": response.model,
                "elapsed_sec": round(time.monotonic() - started_at, 2),
                "response_format": "text",
                "raw_output": preview_text(response.content),
                "cleaned_output": preview_text(content),
                "prompt_chars": len(system_prompt) + len(user_text),
                "history_turns": self.quick_reply_history_turns,
                "max_tokens": self.quick_reply_max_tokens,
            })
        return content

    def _render_quick_history(self, recent_history: list) -> str:
        items = recent_history[-max(0, self.quick_reply_history_turns * 2):]
        lines = []
        budget = max(0, self.quick_reply_history_chars)
        for item in items:
            role = item["role"]
            content = item["content"]
            label = "用户" if role == "user" else "助手"
            line = f"{label}：{str(content).strip()}"
            if budget and len(line) > budget:
                line = line[:budget] + "..."
            lines.append(line)
            if budget:
                budget -= len(line)
                if budget <= 0:
                    break
        return "\n".join(lines)

    def _generate_interaction_content(self, interaction_type: str, character) -> str:
        """根据 interaction_type 使用模板生成交互引导内容。"""
        name = character.name
        templates = {
            "breathing": (
                f"{name}轻轻靠近你，邀请你一起做一个小练习。\n\n"
                "我们一起来做四次慢呼吸吧：\n"
                "吸气……数到四……\n"
                "屏住……数到四……\n"
                "呼气……数到四……\n"
                "再来一次，不着急，按照自己的节奏来。\n\n"
                "当你准备好了，可以告诉我你现在感觉怎么样。"
            ),
            "body_scan": (
                f"{name}在旁边安静地陪着你。\n\n"
                "你可以试着从头到脚慢慢感受一下自己的身体：\n"
                "- 感受你的额头，是不是有一点紧？\n"
                "- 感受你的肩膀，能不能轻轻放下一点？\n"
                "- 感受你的双手，它们现在是什么温度？\n"
                "- 感受你的脚底，它们和地面接触的感觉是怎样的？\n\n"
                "不着急，一个一个来。感受到了什么都可以告诉我。"
            ),
            "mood_check": (
                f"{name}想先了解一下你现在的心情。\n\n"
                "如果用一个词来形容你此刻的感觉，会是什么？\n"
                "不用想太多，第一个浮现的词就好。\n\n"
                "或者你也可以说：现在我什么感觉都没有，那也没关系。"
            ),
            "mini_game": (
                f"{name}想到了一个小游戏，也许能帮你稍微放松一下。\n\n"
                "我们来玩「五个感官」吧：\n"
                "试着找到身边——\n"
                "- 一样你可以看到的东西\n"
                "- 一样你可以摸到的东西\n"
                "- 一样你可以听到的东西\n\n"
                "不一定要全找到，找到一个就很好。准备好了就告诉我。"
            ),
        }
        return templates.get(interaction_type, templates["breathing"])

    @staticmethod
    def _sse_event(event_type: str, data) -> str:
        """构造 SSE 格式事件字符串。"""
        payload = json.dumps(data, ensure_ascii=False)
        return f"event: {event_type}\ndata: {payload}\n\n"

    def _choose_reply_roles(
        self,
        session_id: str,
        user_text: str,
        *,
        state_profiles: list[dict] | None = None,
        debug_trace: dict | None = None,
    ) -> dict:
        fallback = auto_select_character(user_text)
        messages = self.store.get_session_messages(session_id)
        if state_profiles is None:
            state_profiles = self.store.list_state_profiles()
        prompt = read_prompt("route_plan.md").format(
            character_text=render_character_options(),
            history_text=render_conversation_history(messages[-12:]),
            profile_text=render_state_profiles(state_profiles),
            fallback_character_id=fallback.id,
        )
        router_started_at = time.monotonic()
        try:
            response = self._chat(
                [
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": user_text},
                ],
                call_type="route_plan",
                session_id=session_id,
                temperature=0.2,
                max_tokens=650,
                response_format={"type": "json_object"},
                thinking="enabled",
                reasoning_effort="high",
            )
            raw_plan = json.loads(response.content)
            if debug_trace is not None:
                debug_trace["llm_calls"].append({
                    "name": "turn_planner",
                    "model": response.model,
                    "elapsed_sec": round(time.monotonic() - router_started_at, 2),
                    "response_format": "json_object",
                    "raw_output": preview_text(response.content),
                    "parsed_output": raw_plan,
                })
        except Exception:
            self.logger.exception("role router failed; fallback=%s", fallback.id)
            raw_plan = {}
            if debug_trace is not None:
                debug_trace["llm_calls"].append({
                    "name": "turn_planner",
                    "model": "unknown",
                    "elapsed_sec": round(time.monotonic() - router_started_at, 2),
                    "response_format": "json_object",
                    "error": "本轮策略规划失败，已回退到关键词规则。",
                    "fallback_character_id": fallback.id,
                })
        return normalize_response_plan(raw_plan, fallback.id)

    def close_session(self, session_id: str) -> dict:
        started_at = time.monotonic()
        self.logger.info("close_session start session=%s", session_id)
        existing_session = self.store.get_session(session_id)
        existing_journals = self.store.list_journals(session_id=session_id, limit=1)
        latest_message_at = self.store.latest_message_at(session_id)
        latest_journal_at = existing_journals[0]["created_at"] if existing_journals else None
        has_new_messages = bool(
            latest_message_at
            and latest_journal_at
            and latest_message_at > latest_journal_at
        )
        if existing_session and existing_session.get("ended_at") and existing_journals and not has_new_messages:
            memories = self.store.list_memories(session_id=session_id)
            memory_events = self.store.list_memory_events(session_id=session_id)
            self.logger.info(
                "close_session reuse session=%s elapsed=%.2fs memories=%s memory_events=%s",
                session_id,
                time.monotonic() - started_at,
                len(memories),
                len(memory_events),
            )
            return {
                "journal": existing_journals[0],
                "memories": memories,
                "memory_events": memory_events,
                "state_profiles": [],
                "reused": True,
            }
        messages = self.store.get_session_messages(session_id)
        transcript = "\n".join(
            f"{row['role']}: {row['content']}" for row in messages
        )

        def run_phase(name: str, func, *args):
            phase_started_at = time.monotonic()
            self.logger.info("close_session phase start session=%s phase=%s", session_id, name)
            result = func(*args)
            self.logger.info(
                "close_session phase done session=%s phase=%s elapsed=%.2fs",
                session_id,
                name,
                time.monotonic() - phase_started_at,
            )
            return result

        with ThreadPoolExecutor(max_workers=3, thread_name_prefix="close-session") as executor:
            journal_future = executor.submit(run_phase, "journal", self._write_journal, transcript)
            memory_future = executor.submit(run_phase, "memory_extract", self._extract_memories, transcript)
            state_future = executor.submit(
                run_phase,
                "state_profile_review",
                self._review_state_profiles,
                session_id,
                transcript,
            )

            try:
                candidates = memory_future.result()
            except Exception:
                self.logger.exception("memory extraction failed session=%s", session_id)
                candidates = []

            memory_results = run_phase("memory_merge", self._merge_memories, session_id, candidates)

            try:
                journal = journal_future.result()
            except Exception:
                self.logger.exception("journal generation failed session=%s", session_id)
                journal = {}

            try:
                state_profile_results = state_future.result()
            except Exception:
                self.logger.exception("state profile review failed session=%s", session_id)
                state_profile_results = []

        self.store.add_journal(session_id, journal)
        self._auto_mental_status_record(session_id, journal)
        self.store.end_session(session_id)
        self.logger.info(
            "close_session done session=%s elapsed=%.2fs memory_results=%s state_profile_results=%s",
            session_id,
            time.monotonic() - started_at,
            len(memory_results),
            len(state_profile_results),
        )
        return {
            "journal": journal,
            "memories": memory_results,
            "memory_events": self.store.list_memory_events(session_id=session_id),
            "state_profiles": state_profile_results,
        }

    def _auto_mental_status_record(
        self,
        session_id: str,
        journal: dict[str, Any],
    ) -> None:
        if not journal or not journal.get("summary"):
            return
        try:
            from app.memory.schema import MENTAL_STATUS_MOODS
            prompt = read_prompt("mental_status_extract.md").format(
                moods="、".join(MENTAL_STATUS_MOODS),
            )
            journal_text = json.dumps(journal, ensure_ascii=False, indent=2)
            response = self._chat(
                [
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": journal_text},
                ],
                call_type="mental_status_extract",
                temperature=0.3,
                max_tokens=600,
                response_format={"type": "json_object"},
            )
            status = parse_json_object(response.content)
            if not status.get("mood"):
                self.logger.warning("mental status extraction returned empty mood session=%s", session_id)
                return
            now = datetime.now(timezone.utc)
            self.store.add_mental_status_record({
                "record_date": now.date().isoformat(),
                "record_time": now.strftime("%H:%M"),
                "source_type": "session_generated",
                "source_id": session_id,
                "mood": status.get("mood", ""),
                "mood_intensity": status.get("mood_intensity"),
                "emotions": status.get("emotions", {}),
                "energy_level": status.get("energy_level"),
                "sleep_quality": status.get("sleep_quality"),
                "social_drive": status.get("social_drive"),
                "focus_level": status.get("focus_level"),
                "triggers": status.get("triggers", ""),
                "coping": status.get("coping", ""),
                "notes": status.get("notes", ""),
            })
        except Exception:
            self.logger.exception("auto mental status record failed session=%s", session_id)

    def _write_journal(self, transcript: str) -> dict:
        prompt = read_prompt("journal.md")
        response = self._chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            call_type="journal",
            temperature=0.3,
            max_tokens=800,
            response_format={"type": "json_object"},
        )
        try:
            payload = json.loads(response.content)
        except (TypeError, json.JSONDecodeError):
            self.logger.exception("journal response is not valid JSON")
            return {}
        return payload if isinstance(payload, dict) else {}

    def _extract_memories(self, transcript: str) -> list[dict]:
        prompt = read_prompt("memory_extract.md").replace(
            "{{categories}}", ", ".join(MEMORY_CATEGORIES)
        )
        response = self._chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            call_type="memory_extract",
            temperature=0.2,
            max_tokens=600,
            response_format={"type": "json_object"},
        )
        try:
            payload = json.loads(response.content)
        except (TypeError, json.JSONDecodeError):
            self.logger.exception("memory extraction response is not valid JSON")
            return []
        if not isinstance(payload, dict):
            return []
        memories = payload.get("memories", [])
        valid = []
        for memory in memories[:3]:
            if memory.get("category") in MEMORY_CATEGORIES and memory.get("content"):
                memory["subcategory"] = normalize_memory_subcategory(
                    memory["category"],
                    memory.get("subcategory"),
                )
                memory.setdefault("keywords", [])
                if not isinstance(memory["keywords"], list):
                    memory["keywords"] = []
                valid.append(memory)
        return valid

    def _merge_memories(
        self,
        session_id: str,
        candidates: list[dict],
    ) -> list[dict]:
        results = []
        for candidate in candidates[:3]:
            existing = self.store.find_memory_candidates(candidate)
            try:
                decision = self._decide_memory_merge(candidate, existing)
            except Exception as error:
                self.logger.exception(
                    "memory merge decision failed; fallback=create session=%s error=%s",
                    session_id,
                    error,
                )
                decision = {
                    "action": "create",
                    "target_memory_id": "",
                    "memory": candidate,
                    "reason": "记忆合并判断暂时失败，已保留为新记忆。",
                }
            action = decision.get("action", "create")
            memory = decision.get("memory") or candidate
            reason = decision.get("reason", "")
            target_id = decision.get("target_memory_id", "")

            if action == "ignore":
                self.store.add_memory_event(
                    session_id,
                    action="ignore",
                    memory=candidate,
                    reason=reason,
                )
                results.append({**candidate, "action": "ignore", "reason": reason})
                continue
            if action == "create" or not target_id:
                memory_id = self.store.add_memory(session_id, memory)
                self.store.add_memory_event(
                    session_id,
                    action="create",
                    memory=memory,
                    memory_id=memory_id,
                    reason=reason,
                )
                results.append({**memory, "id": memory_id, "action": "create", "reason": reason})
                continue
            if action in {"merge", "update"}:
                self.store.update_memory(target_id, memory, merge_note=reason)
                self.store.add_memory_event(
                    session_id,
                    action=action,
                    memory=memory,
                    memory_id=target_id,
                    reason=reason,
                )
                results.append({**memory, "id": target_id, "action": action, "reason": reason})
                continue
            if action == "contradict":
                self.store.mark_memory(target_id, status="contradicted", merge_note=reason)
                memory_id = self.store.add_memory(session_id, {**memory, "status": "active"})
                self.store.add_memory_event(
                    session_id,
                    action="contradict",
                    memory=memory,
                    memory_id=memory_id,
                    reason=reason,
                )
                results.append({**memory, "id": memory_id, "action": "contradict", "reason": reason})
                continue
            memory_id = self.store.add_memory(session_id, memory)
            self.store.add_memory_event(
                session_id,
                action="create",
                memory=memory,
                memory_id=memory_id,
                reason=reason,
            )
            results.append({**memory, "id": memory_id, "action": "create", "reason": reason})
        return results

    def _review_state_profiles(self, session_id: str, transcript: str) -> list[dict]:
        current_profiles = self.store.list_state_profiles()
        profile_history = self.store.list_state_profile_versions(limit=30)
        long_term_memories = [
            dict(memory)
            for memory in self.store.recent_memories(limit=24)
        ]
        observations = self._extract_state_profile_observations(
            session_id,
            transcript,
        )
        prompt = read_prompt("state_profile_review.md").format(
            domains=", ".join(STATE_PROFILE_DOMAINS),
            trends=", ".join(STATE_PROFILE_TRENDS),
            current_profiles=render_state_profiles(current_profiles),
            profile_history=render_state_profile_history(profile_history),
            long_term_memories=render_memories(long_term_memories),
            session_observations=preview_text(
                json.dumps(observations, ensure_ascii=False),
                7000,
            ),
        )
        response = self._chat(
            [
                {"role": "system", "content": prompt},
                {
                    "role": "user",
                    "content": "请完成第二阶段融合，并输出六个 domain 的 updates。",
                },
            ],
            call_type="state_profile_review",
            session_id=session_id,
            temperature=0.2,
            max_tokens=2200,
            response_format={"type": "json_object"},
        )
        payload = parse_json_object(response.content)
        updates = payload.get("updates", [])
        if not isinstance(updates, list):
            updates = []
        updates = self._complete_state_profile_updates(updates)
        profiles_by_domain = {
            profile.get("domain"): profile
            for profile in current_profiles
            if profile.get("domain") in STATE_PROFILE_DOMAINS
        }
        existing_domains = set(profiles_by_domain)
        reviewed_domains = set()
        results = []
        for update in updates:
            if not isinstance(update, dict):
                continue
            domain = update.get("domain")
            action = update.get("action", "no_change")
            if domain not in STATE_PROFILE_DOMAINS or domain in reviewed_domains:
                continue
            reviewed_domains.add(domain)
            if action not in {"create", "update", "no_change"}:
                action = "no_change"
            if action == "create" and domain in existing_domains:
                action = "update"
            if action == "update" and domain not in existing_domains:
                action = "create"
            normalized = self._normalize_state_profile_update(
                update,
                action,
                existing_profile=profiles_by_domain.get(domain),
            )
            if action == "no_change":
                results.append({**normalized, "action": action})
                continue
            saved = self.store.upsert_state_profile(
                session_id,
                normalized,
                action=action,
                reason=normalized["reason"],
            )
            results.append(saved)
        return results

    def _extract_state_profile_observations(
        self,
        session_id: str,
        transcript: str,
    ) -> list[dict]:
        prompt = read_prompt("state_profile_observation.md").format(
            domains=", ".join(STATE_PROFILE_DOMAINS),
            trends=", ".join(STATE_PROFILE_TRENDS),
        )
        response = self._chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            call_type="state_profile_observation",
            session_id=session_id,
            temperature=0.1,
            max_tokens=1800,
            response_format={"type": "json_object"},
        )
        payload = parse_json_object(response.content)
        observations = payload.get("observations", [])
        if not isinstance(observations, list):
            observations = []
        by_domain = {
            item.get("domain"): item
            for item in observations
            if isinstance(item, dict) and item.get("domain") in STATE_PROFILE_DOMAINS
        }
        completed = []
        for domain in STATE_PROFILE_DOMAINS:
            item = by_domain.get(domain)
            if item is None:
                item = {
                    "domain": domain,
                    "has_evidence": False,
                    "observation": "",
                    "stage_hint": "",
                    "intensity_hint": 5,
                    "trend_hint": "unknown",
                    "confidence": 0.0,
                    "evidence": [],
                    "support_hint": "",
                }
            completed.append(item)
        return completed

    def _complete_state_profile_updates(self, updates: list[dict]) -> list[dict]:
        by_domain = {
            item.get("domain"): item
            for item in updates
            if isinstance(item, dict) and item.get("domain") in STATE_PROFILE_DOMAINS
        }
        completed = []
        for domain in STATE_PROFILE_DOMAINS:
            item = by_domain.get(domain)
            if item is None:
                item = {
                    "action": "no_change",
                    "domain": domain,
                    "reason": "融合阶段未返回该领域，系统按证据不足处理。",
                }
            completed.append(item)
        return completed

    def _normalize_state_profile_update(
        self,
        update: dict,
        action: str,
        *,
        existing_profile: dict | None = None,
    ) -> dict:
        existing_profile = existing_profile or {}
        new_evidence = update.get("evidence", [])
        if not isinstance(new_evidence, list):
            new_evidence = []
        combined_evidence = []
        for item in [*existing_profile.get("evidence", []), *new_evidence]:
            text = str(item).strip()[:160]
            if text and text not in combined_evidence:
                combined_evidence.append(text)
        try:
            intensity = int(update.get("intensity", existing_profile.get("intensity", 5)))
        except (TypeError, ValueError):
            intensity = 5
        try:
            confidence = float(update.get("confidence", existing_profile.get("confidence", 0.5)))
        except (TypeError, ValueError):
            confidence = 0.5
        trend = str(update.get("trend") or existing_profile.get("trend") or "unknown")
        if trend not in STATE_PROFILE_TRENDS:
            trend = "unknown"
        return {
            "domain": update["domain"],
            "stage": str(
                update.get("stage")
                or existing_profile.get("stage")
                or "尚未形成清晰阶段"
            )[:80],
            "summary": str(
                update.get("summary")
                or existing_profile.get("summary")
                or ""
            )[:1000],
            "intensity": max(1, min(10, intensity)),
            "trend": trend,
            "confidence": max(0.0, min(1.0, confidence)),
            "evidence": combined_evidence[-8:],
            "support_strategy": str(
                update.get("support_strategy")
                or existing_profile.get("support_strategy")
                or ""
            )[:240],
            "reason": str(update.get("reason") or ("本次证据不足以更新。" if action == "no_change" else "本次 session 提供了新的长期状态线索。"))[:160],
        }

    def _decide_memory_merge(
        self,
        candidate: dict,
        existing: list[dict],
    ) -> dict:
        if not existing:
            return {
                "action": "create",
                "target_memory_id": "",
                "memory": candidate,
                "reason": "没有找到同类旧记忆。",
            }
        prompt = read_prompt("memory_merge.md")
        payload = {
            "candidate_memory": candidate,
            "existing_memories": existing,
        }
        response = self._chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
            ],
            call_type="memory_merge",
            temperature=0.2,
            max_tokens=700,
            response_format={"type": "json_object"},
        )
        try:
            decision = parse_json_object(response.content)
        except (json.JSONDecodeError, TypeError, ValueError) as error:
            self.logger.warning(
                "memory merge response invalid; fallback=create error=%s chars=%s",
                error,
                len(response.content or ""),
            )
            return {
                "action": "create",
                "target_memory_id": "",
                "memory": candidate,
                "reason": "记忆合并判断返回格式异常，已保留为新记忆。",
            }
        if decision.get("action") not in {
            "create",
            "merge",
            "update",
            "contradict",
            "ignore",
        }:
            decision["action"] = "create"
        decision.setdefault("target_memory_id", "")
        decision.setdefault("memory", candidate)
        decision.setdefault("reason", "")
        return decision
