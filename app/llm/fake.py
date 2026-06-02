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
            if "策略规划器" in system:
                content = json.dumps(
                    {
                        "user_state": "在复杂情绪里寻找心理机制解释",
                        "core_need": "被理解，并把内在模式理清楚",
                        "risk_level": "low",
                        "response_mode": "insight",
                        "knowledge_needs": ["严苛的内在批判者", "创伤性向内归因", "全能控制感"],
                        "response_guidance": "先承认这种模式曾经保护过用户，再温和区分保护与伤害。",
                        "empathic": {
                            "character_id": "youyou_rabbit",
                            "intent": "先轻轻接住难受",
                        },
                        "pinpoint": {
                            "character_id": "huahua_fox",
                            "intent": "点出正在找结构",
                        },
                        "main": {
                            "character_id": "sensen_deer",
                            "intent": "温柔地整理感受",
                        },
                        "reason": "fake 模式：固定返回三角色分工。",
                    },
                    ensure_ascii=False,
                )
            elif "empathic_text" in system and "pinpoint_text" in system:
                content = json.dumps(
                    {
                        "empathic_action": "soft_lean",
                        "empathic_text": "感受到你心里的困惑和痛。",
                        "pinpoint_action": "tilt_head",
                        "pinpoint_text": "真正累人的，也许是你一直在独自扛着。",
                        "main_reply": (
                            "我听见了。你说的不是一个简单的“今天不开心”，而像是心里有一团东西一直没有被好好放下来。\n\n"
                            "我们可以先不急着解决它，只把它看清楚一点：它是在身体里更紧，还是在关系里更委屈？先分清这一点，就已经是在往内心走近。"
                        ),
                    },
                    ensure_ascii=False,
                )
            elif "candidate_memory" in messages[-1]["content"]:
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
                        "mood_score": 1,
                        "dominant_emotion": "稳定",
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
