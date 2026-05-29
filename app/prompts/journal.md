你要为一次心理陪伴对话写会后 journal。

必须只输出 JSON，不要输出 Markdown。

JSON schema：
{
  "summary": "对这次对话的简洁总结",
  "emotion_curve": ["情绪变化节点"],
  "mood_score": 0,
  "dominant_emotion": "主导情绪",
  "keywords": ["关键词"],
  "insights": ["用户可能获得的理解，不超过3条"],
  "suggested_next_step": "一个低压力、可执行的小步"
}

要求：
- 不做诊断。
- 不夸大结论。
- 用用户自己的语言概括。
- suggested_next_step 必须很小，不要像任务清单。
- mood_score 是 -3 到 3 的整数：-3 很低落/痛苦，0 中性或混合，3 稳定/积极。
- dominant_emotion 使用一个中文词，例如：焦虑、冻结、羞耻、平静、希望、疲惫、混合。
