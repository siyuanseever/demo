import json
import logging
import time
from pathlib import Path

from app.agents.safety import CRISIS_RESPONSE, detect_crisis
from app.characters import CHARACTERS, auto_select_character, get_character
from app.llm.base import LLMClient
from app.knowledge.retriever import KnowledgeRetriever, render_knowledge_cards
from app.memory.schema import MEMORY_CATEGORIES
from app.memory.store import Store


PROMPT_DIR = Path(__file__).resolve().parents[1] / "prompts"


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
        '  "empathic_text": "共情动作短句，18 字以内",\n'
        '  "pinpoint_text": "一句话点明，35 字以内",\n'
        '  "main_reply": "主回复正文，3-6 段，克制但有深度"\n'
        "}\n"
        f"empathic_text 必须由「{empathic.name}」说出，只接住情绪，不分析。\n"
        f"pinpoint_text 必须由「{pinpoint.name}」说出，只点明一个痛点、事实或方向。\n"
        f"main_reply 必须由「{main.name}」说出，承担主要心理陪伴。\n"
        "不要在字段文本前重复动物名字；前端会显示名字。"
    )


def normalize_group_response(raw: dict, route_plan: dict) -> dict:
    return {
        "empathic": {
            "character_id": route_plan["empathic"]["character_id"],
            "text": str(raw.get("empathic_text") or "我在这里，先陪你停一下。")[:120],
        },
        "pinpoint": {
            "character_id": route_plan["pinpoint"]["character_id"],
            "text": str(raw.get("pinpoint_text") or "这里可能有一个很需要被看见的点。")[:180],
        },
        "main": {
            "character_id": route_plan["main"]["character_id"],
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
        if character_id == "auto":
            route_plan = self._choose_reply_roles(session_id, user_text)
            character = get_character(route_plan["main"]["character_id"])
        else:
            character = get_character(character_id)
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

        response = self.llm.chat(
            llm_messages,
            temperature=0.75,
            max_tokens=900,
            response_format={"type": "json_object"} if route_plan else None,
        )
        group_response = None
        reply_content = response.content
        if route_plan:
            try:
                group_response = normalize_group_response(json.loads(response.content), route_plan)
                reply_content = render_group_transcript(group_response)
            except (TypeError, json.JSONDecodeError):
                self.logger.exception("group response parse failed; falling back to raw reply")
        self.store.add_message(
            session_id,
            "assistant",
            reply_content,
            model=response.model,
            metadata={
                "character_id": character.id,
                "route_plan": route_plan,
                "group_response": group_response,
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
        }

    def _choose_reply_roles(self, session_id: str, user_text: str) -> dict:
        fallback = auto_select_character(user_text)
        messages = self.store.get_session_messages(session_id)
        prompt = read_prompt("role_router.md").format(
            character_options=render_character_options(),
            conversation_history=render_conversation_history(messages[-12:]),
        )
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
        except Exception:
            self.logger.exception("role router failed; fallback=%s", fallback.id)
            raw_plan = {}
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
