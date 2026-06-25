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
        thinking: str | None = None,
        reasoning_effort: str | None = None,
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
                        "character_id": "yoran",
                        "expression_id": "serene",
                        "knowledge_needs": ["严苛的内在批判者", "创伤性向内归因", "全能控制感"],
                        "memory_queries": ["道德感", "自我苛责", "完美主义", "欲望压抑"],
                        "knowledge_queries": ["过度道德化", "严苛内在批判者", "创伤性向内归因"],
                        "response_guidance": "先承认这种模式曾经保护过用户，再温和区分保护与伤害。",
                        "reason": "fake 模式：固定返回悠然兔平静表情。",
                    },
                    ensure_ascii=False,
                )
            elif '"reply"' in system and "expression_id" in system:
                content = json.dumps(
                    {
                        "reply": (
                            "我听见了。你说的不是一个简单的“今天不开心”，而像是心里有一团东西一直没有被好好放下来。\n\n"
                            "我们可以先不急着解决它，只把它看清楚一点：它是在身体里更紧，还是在关系里更委屈？先分清这一点，就已经是在往内心走近。"
                        ),
                        "expression_id": "serene",
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
            elif "长期状态画像" in system and "updates" in system:
                content = json.dumps(
                    {
                        "updates": [
                            {
                                "action": "create",
                                "domain": "meaning_value",
                                "stage": "正在重新理解道德化自责",
                                "summary": "用户开始把强烈道德感看作曾经的求生策略，同时意识到它也会压抑欲望和真实感受。",
                                "intensity": 7,
                                "trend": "integrating",
                                "confidence": 0.72,
                                "evidence": [
                                    "用户反复询问强烈道德感是否不健康。",
                                    "用户提到自我苛责、完美主义和欲望压抑。",
                                ],
                                "support_strategy": "先去羞耻化，再帮助用户区分价值、念头和自我惩罚。",
                                "reason": "本次 session 提供了明确的长期价值模式线索。",
                            }
                        ]
                    },
                    ensure_ascii=False,
                )
            elif "心流导航" in system and "primary_goal_title" in system:
                content = json.dumps(
                    {
                        "primary_goal_title": "把当前最模糊的问题整理成一页笔记",
                        "primary_goal_reason": "最近的记录反复出现探索、命名和整理的需要。把问题写清楚，比马上找到答案更符合当前状态。",
                        "primary_goal_next_step": "先写下问题、三个已知线索和一个还不确定的地方。",
                        "primary_goal_challenge": "适中",
                        "secondary_goal_title": "给身体留一次不带任务的休息",
                        "secondary_goal_reason": "近期的疲惫会影响注意力，保留恢复空间能让主要目标更容易持续。",
                        "secondary_goal_next_step": "找十分钟离开屏幕，只感受身体需要什么。",
                        "secondary_goal_challenge": "轻量",
                        "recent_emotion_summary": "近期同时有好奇、疲惫和一点焦虑。好奇心仍然在，但压力会把注意力拉向结果，因此更适合清楚而有限的小目标。",
                        "recent_emotion_tags": ["好奇", "疲惫", "焦虑"],
                        "flow_support": "先明确这一轮只整理问题，不要求解决；关掉一个干扰源，把结束标准设为“留下可继续的线索”。",
                        "memory_cues": [
                            "记录里反复出现：面对开放问题时，你更容易持续投入。",
                            "你曾经在独处、夜晚和没有明确答案的探索中感到更有生命力。",
                            "当任务被缩小到可以开始的一步时，冻结感会减轻。",
                        ],
                        "core_insight": "过去这一个月里，\n你最有生命力的时刻，\n常出现在把模糊感受慢慢说清的时候。",
                        "core_insight_detail": "fake 模式下，系统观察到用户在探索内在结构、允许复杂感受并尝试表达时，会比单纯压住自己更有流动感。这份观察用于验证星图接口和 iOS 展示链路。",
                        "recent_pattern_title": "最近的模式",
                        "recent_pattern_items": ["察觉", "命名", "整理"],
                        "recent_pattern_detail": "最近你似乎会先感觉到一团说不清的东西，随后尝试命名它，再把它慢慢整理成能被理解的线索。这种节奏本身已经是一种稳定下来的方式。",
                        "flow_condition_title": "容易进入星流的时候",
                        "flow_condition_items": ["夜晚", "独处", "开放问题"],
                        "flow_condition_detail": "当外界催促较少、你有一点独处空间，而且面对的不是标准答案题，而是允许探索的问题时，你更容易进入一种有连贯感的状态。",
                        "gentle_reminder_title": "一个温柔提醒",
                        "gentle_reminder": "最近不必急着\n把自己说服，先把\n真实感受留住也很好。",
                        "gentle_reminder_detail": "这段时间更重要的也许不是迅速得出结论，而是允许那些尚未成形的感受先存在。只要它们被看见，就已经在慢慢变化。",
                        "source_summary": "fake 模式：基于最近材料生成的月度星图样例。",
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
