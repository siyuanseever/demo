import json
import logging
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.agents.safety import CRISIS_RESPONSE, detect_crisis
from app.characters import (
    CHARACTERS,
    auto_select_character,
    expression_options,
    get_character,
    normalize_expression_id,
)
from app.llm.base import LLMClient
from app.knowledge.retriever import KnowledgeRetriever, render_knowledge_cards
from app.memory.schema import MEMORY_CATEGORIES, STATE_PROFILE_DOMAINS, STATE_PROFILE_TRENDS
from app.memory.store import Store


PROMPT_DIR = Path(__file__).resolve().parents[1] / "prompts"


RISK_LEVELS = {"low", "medium", "high"}
RESPONSE_MODES = {"stabilize", "validate", "insight", "boundary", "action", "mixed"}


def read_prompt(name: str) -> str:
    return (PROMPT_DIR / name).read_text(encoding="utf-8")


def render_memories(memories: list) -> str:
    if not memories:
        return "暂无长期记忆。"
    lines = []
    for memory in memories:
        keywords = memory["keywords"]
        if isinstance(keywords, str):
            try:
                keywords = json.loads(keywords)
            except json.JSONDecodeError:
                keywords = []
        lines.append(
            f"- [{memory['category']}/{memory['subcategory']}] {memory['content']}"
            f"（关键词：{'、'.join(keywords)}；证据：{memory['evidence']}）"
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
    return (
        "\n\n本轮必须输出 JSON，不要输出 Markdown，不要输出 JSON 以外的正文。\n"
        "JSON schema：\n"
        "{\n"
        '  "reply": "最终回复正文，3-7 段，克制但有心理陪伴深度",\n'
        '  "expression_id": "最终表情 id，必须是当前形态可用表情之一"\n'
        "}\n"
        f"当前形态只能是「{character.name}」，不要切换成其他形态说话。\n"
        f"建议表情是 {expression_id}。如果最终回复的情绪更适合当前形态的另一个可用表情，可以改 expression_id。\n"
        f"当前形态可用表情：{expression_options(character)}。\n"
        "reply 字段里不要写角色名，不要写动作括号，不要写“表情：xxx”。"
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
        prompt = (
            "你是森森物语 App 首页的一句话陪伴文案生成器。\n"
            "请根据用户最近的状态、记忆、日记摘要，生成一句中文短句。\n"
            "要求：\n"
            "- 只输出一句话，不要标题，不要解释，不要 JSON。\n"
            "- 语气安静、温柔、稳定，不要鸡汤，不要命令用户变好。\n"
            "- 22 到 42 个汉字左右，可以有一个逗号，最多一个句号。\n"
            "- 不要使用“加油”“一切都会好起来的”这类固定模板。\n"
            "- 如果用户喜欢过某些句子，学习它们的节奏和关注点；不要直接复读。\n"
            "- 如果用户不喜欢过某些句子，避免相似的空泛表达。\n"
        )
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
            response = self.llm.chat(
                [
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": user_context},
                ],
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

    def generate_star_map_insight(self) -> dict:
        now = datetime.now(timezone.utc)
        recent_journals = self.store.list_journals(limit=80)
        recent_messages = self.store.list_messages(limit=300)
        state_profiles = self.store.list_state_profiles(limit=8)
        memories = self.store.list_memories(limit=20)

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

        selected_memories = self._filter_items_since(memories, "updated_at", period_start)
        fallback = self._fallback_star_map_insight(
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
                    "keywords": item.get("keywords", []),
                    "updated_at": item.get("updated_at", ""),
                }
                for item in selected_memories[:10]
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
            response = self.llm.chat(
                [
                    {"role": "system", "content": read_prompt("star_map_monthly_review.md")},
                    {"role": "user", "content": json.dumps(context, ensure_ascii=False)},
                ],
                temperature=0.3,
                max_tokens=1200,
                response_format={"type": "json_object"},
            )
            payload = json.loads(response.content)
            if isinstance(payload, dict):
                normalized = self._normalize_star_map_payload(payload, fallback=fallback)
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

    def _normalize_star_map_payload(self, payload: dict, fallback: dict) -> dict:
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

    def _fallback_star_map_insight(
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

        return {
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
        route_plan = None
        debug_trace = {
            "mode": "rabbit_auto" if character_id == "auto" else "manual_rabbit_form",
            "steps": [],
            "llm_calls": [],
        }
        state_profiles = self.store.list_state_profiles()
        if character_id == "auto":
            route_plan = self._choose_reply_roles(
                session_id,
                user_text,
                state_profiles=state_profiles,
                debug_trace=debug_trace,
            )
            character = get_character(route_plan["character_id"])
            debug_trace["steps"].append({
                "name": "turn_planner",
                "status": "done",
                "summary": "已完成本轮状态、需求、回复模式、兔子形态与表情规划。",
                "output": route_plan,
            })
        else:
            character = get_character(character_id)
            route_plan = None
            debug_trace["steps"].append({
                "name": "manual_character",
                "status": "done",
                "summary": f"使用手动选择角色：{character.name}。",
            })
        self.logger.info(
            "reply start session=%s character=%s user_chars=%s",
            session_id,
            character.id,
            len(user_text),
        )
        self.store.add_message(session_id, "user", user_text)
        if detect_crisis(user_text):
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
                "route_plan": route_plan,
                "debug_trace": {
                    **debug_trace,
                    "steps": debug_trace["steps"] + [{
                        "name": "safety",
                        "status": "triggered",
                        "summary": "命中安全兜底回复，未继续调用生成模型。",
                    }],
                },
            }

        messages = self.store.get_session_messages(session_id)
        memory_queries = route_plan.get("memory_queries", []) if route_plan else []
        knowledge_queries = []
        if route_plan:
            knowledge_queries = route_plan.get("knowledge_needs", []) + route_plan.get("knowledge_queries", [])
        memories = self.store.search_memories(
            user_text,
            query_terms=memory_queries,
            limit=8,
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
        knowledge_cards = self.knowledge.retrieve(
            user_text,
            memory_keywords=[] if route_plan else memory_keywords,
            query_terms=knowledge_queries,
            limit=3,
        )
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
            },
        })
        system_prompt = read_prompt("persona.md").format(
            character_profile=character.prompt,
            current_character_name=character.name,
            conversation_history=render_conversation_history(messages[:-1]),
            memories=render_memories(memories),
            state_profiles=render_state_profiles(state_profiles),
            knowledge_cards=render_knowledge_cards(knowledge_cards),
            role_plan=render_role_plan(route_plan),
        )
        if route_plan:
            system_prompt += render_rabbit_response_instruction(route_plan)
        llm_messages = [{"role": "system", "content": system_prompt}]
        llm_messages.append({"role": "user", "content": user_text})

        generation_started_at = time.monotonic()
        response = self.llm.chat(
            llm_messages,
            temperature=0.75,
            max_tokens=1100,
            response_format={"type": "json_object"} if route_plan else None,
            thinking="disabled",
        )
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
        prompt = read_prompt("role_router.md").format(
            character_options=render_character_options(),
            conversation_history=render_conversation_history(messages[-12:]),
            state_profiles=render_state_profiles(state_profiles),
        )
        router_started_at = time.monotonic()
        try:
            response = self.llm.chat(
                [
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": user_text},
                ],
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

            journal = journal_future.result()

            try:
                state_profile_results = state_future.result()
            except Exception:
                self.logger.exception("state profile review failed session=%s", session_id)
                state_profile_results = []

        self.store.add_journal(session_id, journal)
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

    def _write_journal(self, transcript: str) -> dict:
        prompt = read_prompt("journal.md")
        response = self.llm.chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            temperature=0.3,
            max_tokens=800,
            response_format={"type": "json_object"},
        )
        return json.loads(response.content)

    def _extract_memories(self, transcript: str) -> list[dict]:
        prompt = read_prompt("memory_extract.md").replace(
            "{{categories}}", ", ".join(MEMORY_CATEGORIES)
        )
        response = self.llm.chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            temperature=0.2,
            max_tokens=600,
            response_format={"type": "json_object"},
        )
        payload = json.loads(response.content)
        memories = payload.get("memories", [])
        valid = []
        for memory in memories[:3]:
            if memory.get("category") in MEMORY_CATEGORIES and memory.get("content"):
                memory.setdefault("subcategory", "general")
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
            decision = self._decide_memory_merge(candidate, existing)
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
        prompt = read_prompt("state_profile_review.md").format(
            domains=", ".join(STATE_PROFILE_DOMAINS),
            trends=", ".join(STATE_PROFILE_TRENDS),
            current_profiles=render_state_profiles(current_profiles),
            profile_history=render_state_profile_history(profile_history),
        )
        response = self.llm.chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            temperature=0.2,
            max_tokens=900,
            response_format={"type": "json_object"},
        )
        payload = json.loads(response.content)
        updates = payload.get("updates", [])
        if not isinstance(updates, list):
            return []
        existing_domains = {profile.get("domain") for profile in current_profiles}
        results = []
        for update in updates[:3]:
            if not isinstance(update, dict):
                continue
            domain = update.get("domain")
            action = update.get("action", "no_change")
            if domain not in STATE_PROFILE_DOMAINS:
                continue
            if action not in {"create", "update", "no_change"}:
                action = "no_change"
            if action == "create" and domain in existing_domains:
                action = "update"
            if action == "update" and domain not in existing_domains:
                action = "create"
            normalized = self._normalize_state_profile_update(update, action)
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

    def _normalize_state_profile_update(self, update: dict, action: str) -> dict:
        evidence = update.get("evidence", [])
        if not isinstance(evidence, list):
            evidence = []
        try:
            intensity = int(update.get("intensity", 5))
        except (TypeError, ValueError):
            intensity = 5
        try:
            confidence = float(update.get("confidence", 0.5))
        except (TypeError, ValueError):
            confidence = 0.5
        trend = str(update.get("trend") or "unknown")
        if trend not in STATE_PROFILE_TRENDS:
            trend = "unknown"
        return {
            "domain": update["domain"],
            "stage": str(update.get("stage") or "尚未形成清晰阶段")[:80],
            "summary": str(update.get("summary") or "")[:600],
            "intensity": max(1, min(10, intensity)),
            "trend": trend,
            "confidence": max(0.0, min(1.0, confidence)),
            "evidence": [str(item)[:160] for item in evidence if str(item).strip()][:5],
            "support_strategy": str(update.get("support_strategy") or "")[:240],
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
        response = self.llm.chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
            ],
            temperature=0.2,
            max_tokens=700,
            response_format={"type": "json_object"},
        )
        decision = json.loads(response.content)
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
