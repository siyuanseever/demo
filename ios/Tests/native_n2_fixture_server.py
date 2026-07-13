from __future__ import annotations

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def do_POST(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length) if content_length else b"{}"
        if self.path != "/chat/completions":
            self.send_error(404)
            return

        payload = json.loads(raw_body)
        prompt = "\n".join(item.get("content", "") for item in payload.get("messages", []))
        if "你正在生成即时回应" in prompt:
            content = json.dumps(
                {"reply": "先接住你", "expression_id": "sad_1"},
                ensure_ascii=False,
            )
        elif "策略规划器" in prompt:
            time.sleep(0.08)
            next_action = "quick_only" if "用户：简单问候" in prompt else "deep"
            content = json.dumps(
                {
                    "next_action": next_action,
                    "user_state": "有些焦虑",
                    "core_need": "被理解",
                    "risk_level": "low",
                    "response_mode": "insight",
                    "character_id": "yoyo",
                    "expression_id": "sad_1",
                    "knowledge_needs": [],
                    "memory_queries": [],
                    "knowledge_queries": [],
                    "response_guidance": "在快速回应后补充一个新观察",
                    "reason": "需要认知增量",
                    "action_reply": "",
                },
                ensure_ascii=False,
            )
        else:
            content = json.dumps(
                {"reply": "再一起看深一点", "expression_id": "thinking"},
                ensure_ascii=False,
            )

        body = json.dumps(
            {"choices": [{"message": {"role": "assistant", "content": content}}]},
            ensure_ascii=False,
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    port_file = Path(sys.argv[1])
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port_file.write_text(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
