import json
import logging
import time
import uuid
from pathlib import Path

from app.agents.safety import CRISIS_RESPONSE, detect_crisis
from app.characters import CHARACTERS, auto_select_character, get_character
from app.llm.base import LLMClient
from app.knowledge.retriever import KnowledgeRetriever, render_knowledge_cards
from app.memory.schema import MEMORY_CATEGORIES
from app.memory.store import Store


PROMPT_DIR = Path(__file__).resolve().parents[1] / "prompts"


ROLE_ACTIONS = {
    "soft_lean": "轻轻贴近",
    "tilt_head": "歪头看向你",
    "slow_nod": "慢慢点头",
    "warm_glow": "轻轻发亮",
    "steady_guard": "安静守住",
    "small_breath": "陪你呼一口气",
}

RISK_LEVELS = {"low", "medium", "high"}
RESPONSE_MODES = {"stabilize", "validate", "insight", "boundary", "action", "mixed"}
GROUP_RESPONSE_ORDER = ("empathy", "need", "main", "anchor")


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
        )
    return "\n".join(lines)


def _normalize_role_id(value: str | None, fallback_id: str, used: set[str]) -> str:
    if value in CHARACTERS and value not in used:
        used.add(value)
        return value
    for character_id in CHARACTERS:
        if character_id not in used:
            used.add(character_id)
            return character_id
    return fallback_id


def _short_text(value: object, fallback: str, limit: int) -> str:
    text = str(value or "").strip()
    if not text:
        text = fallback
    return text[:limit]


def _normalize_choice(value: object, allowed: set[str], fallback: str) -> str:
    text = str(value or "").strip().lower()
    return text if text in allowed else fallback


def _normalize_knowledge_needs(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    needs = []
    for item in value:
        text = str(item or "").strip()
        if text and text not in needs:
            needs.append(text[:32])
    return needs[:5]


def _role_payload(raw_plan: dict, key: str, legacy_key: str | None = None) -> dict:
    payload = raw_plan.get(key)
    if not isinstance(payload, dict) and legacy_key:
        payload = raw_plan.get(legacy_key)
    return payload if isinstance(payload, dict) else {}


def normalize_role_plan(raw_plan: dict, fallback_main_id: str) -> dict:
    if not isinstance(raw_plan, dict):
        raw_plan = {}
    used: set[str] = set()
    main_id = _normalize_role_id(
        _role_payload(raw_plan, "main").get("character_id") or fallback_main_id,
        fallback_main_id,
        used,
    )
    empathy_id = _normalize_role_id(
        _role_payload(raw_plan, "empathy", "empathic").get("character_id"),
        fallback_main_id,
        used,
    )
    need_id = _normalize_role_id(
        _role_payload(raw_plan, "need", "pinpoint").get("character_id"),
        fallback_main_id,
        used,
    )
    anchor_id = _normalize_role_id(
        _role_payload(raw_plan, "anchor").get("character_id"),
        fallback_main_id,
        used,
    )
    empathy_payload = _role_payload(raw_plan, "empathy", "empathic")
    need_payload = _role_payload(raw_plan, "need", "pinpoint")
    main_payload = _role_payload(raw_plan, "main")
    anchor_payload = _role_payload(raw_plan, "anchor")
    return {
        "user_state": _short_text(raw_plan.get("user_state"), "需要进一步理解用户此刻状态。", 60),
        "core_need": _short_text(raw_plan.get("core_need"), "被接住，并获得一点清晰感。", 60),
        "risk_level": _normalize_choice(raw_plan.get("risk_level"), RISK_LEVELS, "low"),
        "response_mode": _normalize_choice(raw_plan.get("response_mode"), RESPONSE_MODES, "mixed"),
        "knowledge_needs": _normalize_knowledge_needs(raw_plan.get("knowledge_needs")),
        "response_guidance": _short_text(
            raw_plan.get("response_guidance"),
            "先承接，再给出克制的心理学解释；避免替用户下过重结论。",
            140,
        ),
        "empathy": {
            "character_id": empathy_id,
            "intent": str(empathy_payload.get("intent") or "先接住用户表层情绪。")[:80],
        },
        "need": {
            "character_id": need_id,
            "intent": str(need_payload.get("intent") or "点明用户背后真正需要什么。")[:80],
        },
        "main": {
            "character_id": main_id,
            "intent": str(main_payload.get("intent") or "结合心理学视角做主要回应。")[:80],
        },
        "anchor": {
            "character_id": anchor_id,
            "intent": str(anchor_payload.get("intent") or "留下一句轻而稳的收束话。")[:80],
        },
        "reason": str(raw_plan.get("reason") or "根据用户当前表达的情绪强度、问题类型和需要的支持方式选择。")[:160],
    }


def render_role_plan(route_plan: dict | None) -> str:
    if not route_plan:
        return "本轮是单角色回复。不要加入其他动物的短句。"
    empathy = get_character(route_plan["empathy"]["character_id"])
    need = get_character(route_plan["need"]["character_id"])
    main = get_character(route_plan["main"]["character_id"])
    anchor = get_character(route_plan["anchor"]["character_id"])
    return (
        "本轮是四角色协作回复，但最终只输出一条结构化消息。\n"
        "本轮策略规划：\n"
        f"- 用户状态：{route_plan['user_state']}\n"
        f"- 核心需要：{route_plan['core_need']}\n"
        f"- 风险等级：{route_plan['risk_level']}\n"
        f"- 回复模式：{route_plan['response_mode']}\n"
        f"- 知识需求：{'、'.join(route_plan['knowledge_needs']) if route_plan['knowledge_needs'] else '暂无明确知识卡需求'}\n"
        f"- 写作提醒：{route_plan['response_guidance']}\n"
        f"1. 共情承接：{empathy.name}。先用一句很短的话描述并接住用户当前感受，不分析。"
        f"意图：{route_plan['empathy']['intent']}\n"
        f"2. 需求点明：{need.name}。随后用一句短话点明用户背后的需要、渴望或保护性动机。"
        f"意图：{route_plan['need']['intent']}\n"
        f"3. 主回复：{main.name}。由它承担主要心理陪伴和解释。"
        f"意图：{route_plan['main']['intent']}\n"
        f"4. 收束锚点：{anchor.name}。最后留下一句很短、可带走的鼓励或提醒。"
        f"意图：{route_plan['anchor']['intent']}\n"
        "总长度仍要克制，不要让动物互相聊天。"
    )


def render_group_response_instruction(route_plan: dict) -> str:
    empathy = get_character(route_plan["empathy"]["character_id"])
    need = get_character(route_plan["need"]["character_id"])
    main = get_character(route_plan["main"]["character_id"])
    anchor = get_character(route_plan["anchor"]["character_id"])
    return (
        "\n\n本轮必须输出 JSON，不要输出 Markdown，不要输出 JSON 以外的正文。\n"
        "JSON schema：\n"
        "{\n"
        '  "empathy_action": "动作 id，只能从 soft_lean, slow_nod, warm_glow, steady_guard, small_breath 中选择",\n'
        '  "empathy_text": "共情承接短句，24 字以内",\n'
        '  "need_action": "动作 id，只能从 tilt_head, slow_nod, steady_guard, warm_glow 中选择",\n'
        '  "need_text": "需求点明短句，45 字以内",\n'
        '  "main_reply": "主回复正文，3-6 段，克制但有深度",\n'
        '  "anchor_action": "动作 id，只能从 warm_glow, steady_guard, small_breath, slow_nod 中选择",\n'
        '  "anchor_text": "收束锚点短句，32 字以内"\n'
        "}\n"
        f"empathy_text 必须由「{empathy.name}」说出，只描述并接住用户感受；不要写角色名字，不要写动作描写。\n"
        f"need_text 必须由「{need.name}」说出，只点明用户背后的需要、渴望或保护性动机；不要写角色名字，不要写动作描写。\n"
        f"main_reply 必须由「{main.name}」说出，承担主要心理陪伴。\n"
        f"anchor_text 必须由「{anchor.name}」说出，只留一句很短的收束锚点；不要写角色名字，不要写动作描写。\n"
        "动作只能放进 *_action 字段。不要在任何 *_text 字段里写“歪头看你、轻轻贴近你、点点头”这类动作。"
    )


def normalize_action(value: str | None, fallback: str) -> str:
    return value if value in ROLE_ACTIONS else fallback


def clean_short_text(text: str, character_name: str) -> str:
    cleaned = text.strip()
    for separator in ("：", ":", "，", ","):
        prefix = f"{character_name}{separator}"
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):].strip()
    if cleaned.startswith(character_name):
        cleaned = cleaned[len(character_name):].strip(" ：:，,。")
    action_phrases = [
        "歪头看你",
        "歪着头看你",
        "轻轻贴近你",
        "轻轻靠近你",
        "慢慢点头",
        "点点头",
        "轻轻点头",
        "轻轻发亮",
        "安静守住",
        "陪你呼一口气",
    ]
    changed = True
    while changed:
        changed = False
        for phrase in action_phrases:
            if cleaned.startswith(phrase):
                cleaned = cleaned[len(phrase):].strip(" ：:，,。")
                changed = True
    return cleaned


def normalize_group_response(raw: dict, route_plan: dict) -> dict:
    empathy = get_character(route_plan["empathy"]["character_id"])
    need = get_character(route_plan["need"]["character_id"])
    anchor = get_character(route_plan["anchor"]["character_id"])
    return {
        "empathy": {
            "character_id": route_plan["empathy"]["character_id"],
            "action": normalize_action(raw.get("empathy_action") or raw.get("empathic_action"), "soft_lean"),
            "text": clean_short_text(
                str(raw.get("empathy_text") or raw.get("empathic_text") or "我在这里，先陪你停一下。"),
                empathy.name,
            )[:120],
        },
        "need": {
            "character_id": route_plan["need"]["character_id"],
            "action": normalize_action(raw.get("need_action") or raw.get("pinpoint_action"), "tilt_head"),
            "text": clean_short_text(
                str(raw.get("need_text") or raw.get("pinpoint_text") or "你可能很想知道，自己真正需要的是什么。"),
                need.name,
            )[:180],
        },
        "main": {
            "character_id": route_plan["main"]["character_id"],
            "action": normalize_action(raw.get("main_action"), "small_breath"),
            "text": str(raw.get("main_reply") or raw.get("reply") or "")[:4000],
        },
        "anchor": {
            "character_id": route_plan["anchor"]["character_id"],
            "action": normalize_action(raw.get("anchor_action"), "warm_glow"),
            "text": clean_short_text(
                str(raw.get("anchor_text") or "你不用靠完美，才配得上安稳。"),
                anchor.name,
            )[:160],
        },
    }


def render_group_transcript(group_response: dict) -> str:
    lines = []
    for key in GROUP_RESPONSE_ORDER:
        item = group_response[key]
        character = get_character(item["character_id"])
        lines.append(f"{character.name}：{item['text']}")
    return "\n\n".join(lines)


def group_response_messages(group_response: dict) -> list[dict]:
    messages = []
    for index, key in enumerate(GROUP_RESPONSE_ORDER):
        item = group_response[key]
        messages.append(
            {
                "group_role": key,
                "group_index": index,
                "character_id": item["character_id"],
                "action": item.get("action", ""),
                "text": item["text"],
            }
        )
    return messages


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
            "mode": "group_auto" if character_id == "auto" else "single_character",
            "steps": [],
            "llm_calls": [],
        }
        if character_id == "auto":
            route_plan = self._choose_reply_roles(session_id, user_text, debug_trace=debug_trace)
            character = get_character(route_plan["main"]["character_id"])
            debug_trace["steps"].append({
                "name": "turn_planner",
                "status": "done",
                "summary": "已完成本轮状态、需求、回复模式与角色分工规划。",
                "output": route_plan,
            })
        else:
            character = get_character(character_id)
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
            self.store.add_message(
                session_id,
                "assistant",
                CRISIS_RESPONSE,
                model="safety",
                metadata={"character_id": character.id},
            )
            self.logger.info("reply safety session=%s", session_id)
            return {
                "reply": CRISIS_RESPONSE,
                "knowledge_cards": [],
                "character": character.to_public_dict(),
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
        memories = self.store.recent_memories()
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
            memory_keywords=memory_keywords,
            limit=3,
        )
        debug_trace["steps"].append({
            "name": "retrieve_context",
            "status": "done",
            "summary": "已读取历史消息、长期记忆，并检索知识卡。",
            "output": {
                "history_messages": max(0, len(messages) - 1),
                "memory_count": len(memories),
                "knowledge_cards": [card.get("title", "") for card in knowledge_cards],
            },
        })
        system_prompt = read_prompt("persona.md").format(
            character_profile=character.prompt,
            current_character_name=character.name,
            conversation_history=render_conversation_history(messages[:-1]),
            memories=render_memories(memories),
            knowledge_cards=render_knowledge_cards(knowledge_cards),
            role_plan=render_role_plan(route_plan),
        )
        if route_plan:
            system_prompt += render_group_response_instruction(route_plan)
        llm_messages = [{"role": "system", "content": system_prompt}]
        llm_messages.append({"role": "user", "content": user_text})

        generation_started_at = time.monotonic()
        response = self.llm.chat(
            llm_messages,
            temperature=0.75,
            max_tokens=1100,
            response_format={"type": "json_object"} if route_plan else None,
        )
        generation_call = {
            "name": "group_response" if route_plan else "single_reply",
            "model": response.model,
            "elapsed_sec": round(time.monotonic() - generation_started_at, 2),
            "response_format": "json_object" if route_plan else "text",
            "raw_output": preview_text(response.content),
        }
        group_response = None
        reply_content = response.content
        if route_plan:
            try:
                group_response = normalize_group_response(json.loads(response.content), route_plan)
                reply_content = render_group_transcript(group_response)
                generation_call["parsed_output"] = group_response
            except (TypeError, json.JSONDecodeError):
                self.logger.exception("group response parse failed; falling back to raw reply")
                generation_call["parse_error"] = "JSON 解析失败，已回退为原始文本。"
        debug_trace["llm_calls"].append(generation_call)
        debug_trace["steps"].append({
            "name": "generate_reply",
            "status": "done",
            "summary": "已生成回复内容。" if not route_plan else "已生成四角色结构化回复。",
            "output": {
                "main_character": character.name,
                "reply_chars": len(reply_content),
                "group_message_count": len(group_response_messages(group_response)) if group_response else 0,
            },
        })
        if group_response:
            group_id = str(uuid.uuid4())
            stored_group_messages = group_response_messages(group_response)
            knowledge_card_ids = [card.get("id", "") for card in knowledge_cards if card.get("id")]
            for item in stored_group_messages:
                metadata = {
                    "character_id": item["character_id"],
                    "route_plan": route_plan,
                    "group_id": group_id,
                    "group_role": item["group_role"],
                    "group_index": item["group_index"],
                    "group_size": len(stored_group_messages),
                    "action": item["action"],
                }
                if item["group_role"] == "main" and knowledge_card_ids:
                    metadata["knowledge_card_ids"] = knowledge_card_ids
                self.store.add_message(
                    session_id,
                    "assistant",
                    item["text"],
                    model=response.model,
                    metadata=metadata,
                )
        else:
            self.store.add_message(
                session_id,
                "assistant",
                reply_content,
                model=response.model,
                metadata={
                    "character_id": character.id,
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
            "reply": group_response["main"]["text"] if group_response else reply_content,
            "group_messages": (
                [
                    {
                        "role": key,
                        "text": group_response[key]["text"],
                        "action": group_response[key].get("action", ""),
                        "character": get_character(group_response[key]["character_id"]).to_public_dict(),
                    }
                    for key in GROUP_RESPONSE_ORDER
                ]
                if group_response
                else []
            ),
            "knowledge_cards": knowledge_cards,
            "character": character.to_public_dict(),
            "route_plan": route_plan,
            "debug_trace": {
                **debug_trace,
                "total_elapsed_sec": round(time.monotonic() - started_at, 2),
                "llm_call_count": len(debug_trace["llm_calls"]),
            },
        }

    def _choose_reply_roles(self, session_id: str, user_text: str, debug_trace: dict | None = None) -> dict:
        fallback = auto_select_character(user_text)
        messages = self.store.get_session_messages(session_id)
        prompt = read_prompt("role_router.md").format(
            character_options=render_character_options(),
            conversation_history=render_conversation_history(messages[-12:]),
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
        return normalize_role_plan(raw_plan, fallback.id)

    def close_session(self, session_id: str) -> dict:
        started_at = time.monotonic()
        self.logger.info("close_session start session=%s", session_id)
        messages = self.store.get_session_messages(session_id)
        transcript = "\n".join(
            f"{row['role']}: {row['content']}" for row in messages
        )
        journal = self._write_journal(transcript)
        candidates = self._extract_memories(transcript)
        memory_results = self._merge_memories(session_id, candidates)
        self.store.add_journal(session_id, journal)
        self.store.end_session(session_id)
        self.logger.info(
            "close_session done session=%s elapsed=%.2fs memory_results=%s",
            session_id,
            time.monotonic() - started_at,
            len(memory_results),
        )
        return {"journal": journal, "memories": memory_results}

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
                results.append({**candidate, "action": "ignore", "reason": reason})
                continue
            if action == "create" or not target_id:
                memory_id = self.store.add_memory(session_id, memory)
                results.append({**memory, "id": memory_id, "action": "create", "reason": reason})
                continue
            if action in {"merge", "update"}:
                self.store.update_memory(target_id, memory, merge_note=reason)
                results.append({**memory, "id": target_id, "action": action, "reason": reason})
                continue
            if action == "contradict":
                self.store.mark_memory(target_id, status="contradicted", merge_note=reason)
                memory_id = self.store.add_memory(session_id, {**memory, "status": "active"})
                results.append({**memory, "id": memory_id, "action": "contradict", "reason": reason})
                continue
            memory_id = self.store.add_memory(session_id, memory)
            results.append({**memory, "id": memory_id, "action": "create", "reason": reason})
        return results

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
