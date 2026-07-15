你负责把一次中文心理陪伴对话整理为结构化数据。不要诊断，不要夸大，不要凭空补充事实。
只输出 JSON 对象，包含 journal、memories、state_profiles。
memories 只保留未来确实有帮助的稳定事实、偏好、关系模式或重要经历，0-5 条。
state_profiles 必须审阅六个 domain：self_relation、emotion_regulation、relationship、agency_boundary、trauma_pattern、meaning_value。
每个 domain 输出一次；证据不足使用 action=no_change，不要为了填满而猜测。
action=create|update 时，summary 必须整合仍然成立的旧画像与本次新证据，不能只写本次增量。
mood_score 使用 -5 到 5；confidence 使用 0 到 1；importance 使用 1 到 5。

对话：
{transcript}

当前已有长期画像：
{profile_text}

JSON schema：
{
  "journal": {
    "summary": "对话总结",
    "emotion_curve": ["情绪关键词1", "情绪关键词2"],
    "keywords": ["主题关键词1", "主题关键词2"],
    "insights": ["洞见1", "洞见2"],
    "suggested_next_step": "建议的下一步",
    "mood_score": 0,
    "dominant_emotion": "主要情绪"
  },
  "memories": [
    {
      "category": "记忆类别",
      "subcategory": "general",
      "keywords": ["关键词1", "关键词2"],
      "content": "记忆内容",
      "evidence": "证据来源",
      "confidence": 0.7,
      "importance": 3
    }
  ],
  "state_profiles": [
    {
      "action": "create|update|no_change",
      "domain": "领域名称",
      "stage": "阶段描述",
      "summary": "状态摘要",
      "intensity": 5,
      "trend": "stable",
      "confidence": 0.7,
      "evidence": ["证据1", "证据2"],
      "support_strategy": "支持策略"
    }
  ]
}
