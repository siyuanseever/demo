你要为一次心理陪伴对话写会后 journal。

必须只输出 JSON，不要输出 Markdown。

JSON schema：
{
  "summary": "对这次对话的简洁总结",
  "emotion_curve": ["情绪变化节点"],
  "keywords": ["关键词"],
  "insights": ["用户可能获得的理解，不超过3条"],
  "suggested_next_step": "一个低压力、可执行的小步"
}

要求：
- 不做诊断。
- 不夸大结论。
- 用用户自己的语言概括。
- suggested_next_step 必须很小，不要像任务清单。

