import json

from app.llm.base import LLMResponse, Message


class FakeClient:
    def chat(
        self,
        messages: list[Message],
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
    ) -> LLMResponse:
        if response_format:
            system = messages[0]["content"]
            if "candidate_memory" in messages[-1]["content"]:
                payload = json.loads(messages[-1]["content"])
                candidate = payload["candidate_memory"]
                existing = payload["existing_memories"]
                if existing:
                    target = existing[0]
                    merged = {
                        **candidate,
                        "content": target["content"] + "；并且用户仍在测试记忆合并能力。",
                        "keywords": list(dict.fromkeys(target.get("keywords", []) + candidate.get("keywords", []))),
                    }
                    content = json.dumps(
                        {
                            "action": "merge",
                            "target_memory_id": target["id"],
                            "memory": merged,
                            "reason": "fake 模式：同类记忆自动合并。",
                        },
                        ensure_ascii=False,
                    )
                else:
                    content = json.dumps(
                        {
                            "action": "create",
                            "target_memory_id": "",
                            "memory": candidate,
                            "reason": "fake 模式：无旧记忆，新增。",
                        },
                        ensure_ascii=False,
                    )
            elif "memories" in system:
                content = json.dumps(
                    {
                        "memories": [
                            {
                                "category": "emotion_pattern",
                                "subcategory": "freeze_response",
                                "keywords": ["测试", "小鹿", "记忆流程"],
                                "content": "用户正在测试小鹿 demo 的基础链路和记忆流程。",
                                "evidence": "用户在本地 Web UI 中发送测试消息。",
                                "confidence": 0.6,
                                "importance": 2,
                            }
                        ]
                    },
                    ensure_ascii=False,
                )
            else:
                content = json.dumps(
                    {
                        "summary": "这是 fake 模型生成的会话总结，用于确认前后端链路正常。",
                        "emotion_curve": ["测试", "等待", "确认"],
                        "keywords": ["测试", "小鹿", "链路"],
                        "insights": ["当前优先目标是确认系统可稳定响应。"],
                        "suggested_next_step": "再发送一条真实问题，观察响应时间和日志。",
                    },
                    ensure_ascii=False,
                )
        else:
            latest_user = next(
                (message["content"] for message in reversed(messages) if message["role"] == "user"),
                "",
            )
            content = f"我听见了。你刚才说：{latest_user}\n\n这是 fake 模型回复，说明 Web UI、后端路由和 SQLite 都是通的。"
        return LLMResponse(content=content, model="fake", raw={})
