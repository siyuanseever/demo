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
        if "本周心流导航" in prompt:
            content = json.dumps(
                {
                    "primary_goal_title": "给自己留一段安静时间",
                    "primary_goal_reason": "最近的记录反复提到压力和边界",
                    "primary_goal_next_step": "今晚留十分钟不处理任务",
                    "primary_goal_challenge": "轻量",
                    "secondary_goal_title": "",
                    "secondary_goal_reason": "",
                    "secondary_goal_next_step": "",
                    "secondary_goal_challenge": "",
                    "recent_emotion_summary": "疲惫里正在长出一点清晰",
                    "recent_emotion_tags": ["疲惫", "觉察"],
                    "flow_support": "从一个不要求结果的小问题开始",
                    "memory_cues": ["高压时更需要清晰边界"],
                    "core_insight": "休息不是退出，而是在恢复选择感",
                    "core_insight_detail": "近期记录显示，先停下来会更容易看清需要。",
                    "recent_pattern_title": "最近的模式",
                    "recent_pattern_items": ["压力", "边界", "休息"],
                    "recent_pattern_detail": "压力升高后，会更需要明确边界。",
                    "flow_condition_title": "容易进入心流的时候",
                    "flow_condition_items": ["安静", "没有结果压力"],
                    "flow_condition_detail": "在不被催促时更容易保持专注。",
                    "gentle_reminder_title": "一个温柔提醒",
                    "gentle_reminder": "这周不用把所有事都处理完。",
                    "gentle_reminder_detail": "先照看最靠近此刻的一件事。",
                    "source_summary": "基于本地日记、记忆和长期状态生成。",
                },
                ensure_ascii=False,
            )
        elif "你正在生成即时回应" in prompt:
            content = json.dumps(
                {"reply": "先接住你", "expression_id": "concerned"},
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
                    "expression_id": "understanding",
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
                {"reply": "再一起看深一点", "expression_id": "understanding"},
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
