import json
from pathlib import Path

from app.agents.safety import CRISIS_RESPONSE, detect_crisis
from app.llm.base import LLMClient
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
        lines.append(
            f"- [{memory['category']}] {memory['content']}（证据：{memory['evidence']}）"
        )
    return "\n".join(lines)


class ConversationOrchestrator:
    def __init__(self, llm: LLMClient, store: Store) -> None:
        self.llm = llm
        self.store = store

    def start_session(self) -> str:
        return self.store.create_session()

    def reply(self, session_id: str, user_text: str) -> str:
        self.store.add_message(session_id, "user", user_text)
        if detect_crisis(user_text):
            self.store.add_message(session_id, "assistant", CRISIS_RESPONSE, model="safety")
            return CRISIS_RESPONSE

        messages = self.store.get_session_messages(session_id)
        memories = self.store.recent_memories()
        system_prompt = read_prompt("persona.md").format(
            memories=render_memories(memories)
        )
        llm_messages = [{"role": "system", "content": system_prompt}]
        llm_messages.extend(
            {"role": row["role"], "content": row["content"]} for row in messages[-12:]
        )

        response = self.llm.chat(llm_messages, temperature=0.75, max_tokens=1400)
        self.store.add_message(
            session_id,
            "assistant",
            response.content,
            model=response.model,
        )
        return response.content

    def close_session(self, session_id: str) -> dict:
        messages = self.store.get_session_messages(session_id)
        transcript = "\n".join(
            f"{row['role']}: {row['content']}" for row in messages
        )
        journal = self._write_journal(transcript)
        memories = self._extract_memories(transcript)
        self.store.add_journal(session_id, journal)
        self.store.add_memories(session_id, memories)
        self.store.end_session(session_id)
        return {"journal": journal, "memories": memories}

    def _write_journal(self, transcript: str) -> dict:
        prompt = read_prompt("journal.md")
        response = self.llm.chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            temperature=0.3,
            max_tokens=1200,
            response_format={"type": "json_object"},
        )
        return json.loads(response.content)

    def _extract_memories(self, transcript: str) -> list[dict]:
        prompt = read_prompt("memory_extract.md").format(
            categories=", ".join(MEMORY_CATEGORIES)
        )
        response = self.llm.chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": transcript},
            ],
            temperature=0.2,
            max_tokens=1000,
            response_format={"type": "json_object"},
        )
        payload = json.loads(response.content)
        memories = payload.get("memories", [])
        valid = []
        for memory in memories[:3]:
            if memory.get("category") in MEMORY_CATEGORIES and memory.get("content"):
                valid.append(memory)
        return valid

