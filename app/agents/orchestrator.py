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


def normalize_role_plan(raw_plan: dict, fallback_main_id: str) -> dict:
    used: set[str] = set()
    main_id = _normalize_role_id(
        (raw_plan.get("main") or {}).get("character_id") or fallback_main_id,
        fallback_main_id,
        used,
    )
    empathic_id = _normalize_role_id(
        (raw_plan.get("empathic") or {}).get("character_id"),
        fallback_main_id,
        used,
    )
    pinpoint_id = _normalize_role_id(
        (raw_plan.get("pinpoint") or {}).get("character_id"),
        fallback_main_id,
        used,
    )
    return {
        "empathic": {
            "character_id": empathic_id,
            "intent": str((raw_plan.get("empathic") or {}).get("intent") or "先接住用户表层情绪。")[:80],
        },
        "pinpoint": {
            "character_id": pinpoint_id,
            "intent": str((raw_plan.get("pinpoint") or {}).get("intent") or "用一句话点出一个可能的痛点。")[:80],
        },
        "main": {
            "character_id": main_id,
            "intent": str((raw_plan.get("main") or {}).get("intent") or "结合心理学视角做主要回应。")[:80],
        },
        "reason": str(raw_plan.get("reason") or "根据用户当前表达的情绪强度、问题类型和需要的支持方式选择。")[:160],
    }


def render_role_plan(route_plan: dict | None) -> str:
    if not route_plan:
        return "本轮是单角色回复。不要加入其他动物的短句。"
    empathic = get_character(route_plan["empathic"]["character_id"])
    pinpoint = get_character(route_plan["pinpoint"]["character_id"])
    main = get_character(route_plan["main"]["character_id"])
    return (
        "本轮是三角色协作回复，但最终只输出一条消息。\n"
        f"1. 共情动作：{empathic.name}。只在开头用一行很短的动作或表情接住表层情绪，不做分析。"
        f"意图：{route_plan['empathic']['intent']}\n"
        f"2. 一句话点明：{pinpoint.name}。随后用一句短话点到一个痛点、盲点或可依靠的事实；可以轻微幽默，但不能刺痛用户。"
        f"意图：{route_plan['pinpoint']['intent']}\n"
        f"3. 主回复：{main.name}。由它承担主要心理陪伴和解释。"
        f"意图：{route_plan['main']['intent']}\n"
        "格式要求：先写两行短句，每行以动物名字开头；然后空一行写主回复。"
        "总长度仍要克制，不要让三只动物互相聊天。"
    )


def render_group_response_instruction(route_plan: dict) -> str:
    empathic = get_character(route_plan["empathic"]["character_id"])
    pinpoint = get_character(route_plan["pinpoint"]["character_id"])
    main = get_character(route_plan["main"]["character_id"])
    return (
        "\n\n本轮必须输出 JSON，不要输出 Markdown，不要输出 JSON 以外的正文。\n"
        "JSON schema：\n"
        "{\n"
        '  "empathic_action": "动作 id，只能从 soft_lean, slow_nod, warm_glow, steady_guard, small_breath 中选择",\n'
        '  "empathic_text": "共情动作短句，18 字以内",\n'
        '  "pinpoint_action": "动作 id，只能从 tilt_head, slow_nod, steady_guard, warm_glow 中选择",\n'
        '  "pinpoint_text": "一句话点明，35 字以内",\n'
        '  "main_reply": "主回复正文，3-6 段，克制但有深度"\n'
        "}\n"
        f"empathic_text 必须由「{empathic.name}」说出，只接住情绪，不分析；不要写角色名字，不要写动作描写。\n"
        f"pinpoint_text 必须由「{pinpoint.name}」说出，只点明一个痛点、事实或方向；不要写角色名字，不要写动作描写。\n"
        f"main_reply 必须由「{main.name}」说出，承担主要心理陪伴。\n"
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
    empathic = get_character(route_plan["empathic"]["character_id"])
    pinpoint = get_character(route_plan["pinpoint"]["character_id"])
    return {
        "empathic": {
            "character_id": route_plan["empathic"]["character_id"],
            "action": normalize_action(raw.get("empathic_action"), "soft_lean"),
            "text": clean_short_text(
                str(raw.get("empathic_text") or "我在这里，先陪你停一下。"),
                empathic.name,
            )[:120],
        },
        "pinpoint": {
            "character_id": route_plan["pinpoint"]["character_id"],
            "action": normalize_action(raw.get("pinpoint_action"), "tilt_head"),
            "text": clean_short_text(
                str(raw.get("pinpoint_text") or "这里可能有一个很需要被看见的点。"),
                pinpoint.name,
            )[:180],
        },
        "main": {
            "character_id": route_plan["main"]["character_id"],
            "action": normalize_action(raw.get("main_action"), "small_breath"),
            "text": str(raw.get("main_reply") or raw.get("reply") or "")[:4000],
        },
    }


def render_group_transcript(group_response: dict) -> str:
    lines = []
    for key in ("empathic", "pinpoint", "main"):
        item = group_response[key]
        character = get_character(item["character_id"])
        lines.append(f"{character.name}：{item['text']}")
    return "\n\n".join(lines)


def group_response_messages(group_response: dict) -> list[dict]:
    messages = []
    for index, key in enumerate(("empathic", "pinpoint", "main")):
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
                "name": "role_router",
                "status": "done",
                "summary": "已选择共情、点明、主回复三个角色。",
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
            max_tokens=900,
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
            "summary": "已生成回复内容。" if not route_plan else "已生成三角色结构化回复。",
            "output": {
                "main_character": character.name,
                "reply_chars": len(reply_content),
                "group_message_count": len(group_response_messages(group_response)) if group_response else 0,
            },
        })
        if group_response:
            group_id = str(uuid.uuid4())
            stored_group_messages = group_response_messages(group_response)
            for item in stored_group_messages:
                self.store.add_message(
                    session_id,
                    "assistant",
                    item["text"],
                    model=response.model,
                    metadata={
                        "character_id": item["character_id"],
                        "route_plan": route_plan,
                        "group_id": group_id,
                        "group_role": item["group_role"],
                        "group_index": item["group_index"],
                        "group_size": len(stored_group_messages),
                        "action": item["action"],
                    },
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
                    for key in ("empathic", "pinpoint", "main")
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
                max_tokens=500,
                response_format={"type": "json_object"},
            )
            raw_plan = json.loads(response.content)
            if debug_trace is not None:
                debug_trace["llm_calls"].append({
                    "name": "role_router",
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
                    "name": "role_router",
                    "model": "unknown",
                    "elapsed_sec": round(time.monotonic() - router_started_at, 2),
                    "response_format": "json_object",
                    "error": "角色调度失败，已回退到关键词规则。",
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
