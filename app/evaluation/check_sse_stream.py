"""
Checker for the web SSE two-stage reply flow.

This is intentionally small and deterministic:
- no real DeepSeek call
- no local web server bind
- no private app database

Run:
    python3 -m app.evaluation.check_sse_stream
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any


def check(condition: bool, message: str, details: Any = None) -> None:
    if not condition:
        suffix = f": {details!r}" if details is not None else ""
        raise AssertionError(message + suffix)


def parse_sse_chunk(chunk: str) -> tuple[str, dict[str, Any]]:
    event_type = "message"
    data = ""
    for line in chunk.strip().splitlines():
        if line.startswith("event: "):
            event_type = line.removeprefix("event: ").strip()
        elif line.startswith("data: "):
            data = line.removeprefix("data: ")
    return event_type, json.loads(data) if data else {}


def check_rendered_web_script() -> None:
    from app.characters import list_characters
    from app.config import get_settings
    from app.web import HTML

    settings = get_settings()
    html = (
        HTML
        .replace("__WEB_TIMEOUT_MS__", str(settings.web_timeout_ms))
        .replace("__CHARACTERS_JSON__", json.dumps(list_characters(), ensure_ascii=False))
    )
    start = html.find("<script>")
    end = html.find("</script>", start)
    check(start >= 0 and end > start, "rendered HTML must contain one browser script")

    script_path = Path(tempfile.gettempdir()) / "xiaolu-rendered-script-check.js"
    script_path.write_text(html[start + len("<script>"):end], encoding="utf-8")
    result = subprocess.run(
        ["node", "--check", str(script_path)],
        text=True,
        capture_output=True,
        check=False,
    )
    check(
        result.returncode == 0,
        "rendered browser script must pass node --check",
        result.stderr or result.stdout,
    )
    script = script_path.read_text(encoding="utf-8")
    check(
        "replaceMessageContent(quickReplyNode" not in script,
        "deep reply must not overwrite the quick reply node",
    )
    check(
        'markMessageFinal(quickReplyNode);' in script
        and 'addMessage("deer", d.reply, d.knowledge_cards || []' in script,
        "web UI must preserve quick reply and append deep reply",
    )


def check_sse_deep_reply_contract() -> None:
    os.environ["APP_DB_PATH"] = str(Path(tempfile.gettempdir()) / f"xiaolu-sse-checker-{uuid.uuid4().hex}.db")
    os.environ["LLM_PROVIDER"] = "fake"
    os.environ["PROMPT_TRACKING_ENABLED"] = "false"

    db_path = Path(os.environ["APP_DB_PATH"])
    if db_path.exists():
        db_path.unlink()

    from app.main import build_orchestrator
    from app.memory.store import message_row_to_dict

    orchestrator = build_orchestrator()
    session_id = orchestrator.start_session()
    events = [
        parse_sse_chunk(chunk)
        for chunk in orchestrator.reply_stream(
            session_id,
            "我最近总是过度自责，想理解一下为什么。",
            character_id="auto",
        )
    ]
    event_types = [event_type for event_type, _ in events]
    check(
        event_types == ["quick_reply", "deep_reply", "final", "done"],
        "deep SSE path must emit quick_reply, deep_reply, final, done in order",
        event_types,
    )

    final_payload = next(payload for event_type, payload in events if event_type == "final")
    check(final_payload.get("quick_reply"), "final payload must include quick_reply")
    check(final_payload.get("deep_reply"), "final payload must include deep_reply")
    debug_trace = final_payload.get("debug_trace") or {}
    check(debug_trace.get("quick_reply"), "debug_trace must include quick_reply for dev panel")
    check(debug_trace.get("deep_reply"), "debug_trace must include deep_reply for dev panel")
    llm_call_names = [call.get("name") for call in debug_trace.get("llm_calls", [])]
    check("quick_reply" in llm_call_names, "debug_trace llm_calls must include quick_reply", llm_call_names)
    check("rabbit_response" in llm_call_names, "debug_trace llm_calls must include rabbit_response", llm_call_names)

    messages = [message_row_to_dict(row) for row in orchestrator.store.get_session_messages(session_id)]
    check([row["role"] for row in messages] == ["user", "assistant", "assistant"], "SSE deep path must persist user, quick assistant, and deep assistant messages")
    assistant_models = [row["model"] for row in messages if row["role"] == "assistant"]
    check(assistant_models == ["quick", "fake"], "deep path must persist quick then final deep assistant replies", assistant_models)
    assistant_stages = [row["metadata"].get("reply_stage", "") for row in messages if row["role"] == "assistant"]
    check(assistant_stages == ["quick", "deep"], "deep path assistant messages must be staged quick then deep", assistant_stages)


def check_sse_quick_reply_contract() -> None:
    os.environ["APP_DB_PATH"] = str(Path(tempfile.gettempdir()) / f"xiaolu-sse-quick-checker-{uuid.uuid4().hex}.db")
    os.environ["LLM_PROVIDER"] = "fake"
    os.environ["PROMPT_TRACKING_ENABLED"] = "false"

    db_path = Path(os.environ["APP_DB_PATH"])
    if db_path.exists():
        db_path.unlink()

    from app.intent.schema import IntentResult
    from app.main import build_orchestrator
    from app.memory.store import message_row_to_dict

    orchestrator = build_orchestrator()
    orchestrator.intent_agent.recognize = lambda user_text, conversation_history=None: IntentResult(
        intent="QUICK_REPLY",
        confidence=0.95,
        user_state="平静闲聊",
        core_need="被简单回应",
        emotion="平静",
        risk_level="low",
        character_id="yoyo-rabbit",
        expression_id="gentle",
        response_mode="validate",
        response_guidance="轻轻接一句即可，不展开长分析。",
        reason="用户只是轻量表达，不需要深度回复。",
    )

    session_id = orchestrator.start_session()
    events = [
        parse_sse_chunk(chunk)
        for chunk in orchestrator.reply_stream(
            session_id,
            "我今天只是有点累，想听你说一句。",
            character_id="auto",
        )
    ]
    event_types = [event_type for event_type, _ in events]
    check(
        event_types == ["quick_reply", "final", "done"],
        "quick SSE path must emit quick_reply, final, done in order",
        event_types,
    )

    final_payload = next(payload for event_type, payload in events if event_type == "final")
    check(final_payload.get("quick_reply"), "quick final payload must include quick_reply")
    check(not final_payload.get("deep_reply"), "quick final payload must not require deep_reply")
    debug_trace = final_payload.get("debug_trace") or {}
    check(debug_trace.get("quick_reply"), "quick debug_trace must include quick_reply for dev panel")
    llm_call_names = [call.get("name") for call in debug_trace.get("llm_calls", [])]
    check("quick_reply" in llm_call_names, "quick debug_trace llm_calls must include quick_reply", llm_call_names)

    messages = [message_row_to_dict(row) for row in orchestrator.store.get_session_messages(session_id)]
    check([row["role"] for row in messages] == ["user", "assistant"], "SSE quick path must persist one user and one assistant message")
    assistant_models = [row["model"] for row in messages if row["role"] == "assistant"]
    check(assistant_models == ["quick"], "quick path must persist the quick assistant reply", assistant_models)


def main() -> None:
    checks = [
        ("rendered web script", check_rendered_web_script),
        ("SSE deep reply contract", check_sse_deep_reply_contract),
        ("SSE quick reply contract", check_sse_quick_reply_contract),
    ]
    for name, func in checks:
        func()
        print(f"PASS {name}")
    print("PASS all SSE stream checks")


if __name__ == "__main__":
    main()
