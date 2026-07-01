你要从一篇日记中同时提取心理状态和长期记忆。这篇日记是用户非常私密的个人日记。

你必须像一个温柔而敏锐的心理陪伴者一样阅读这篇日记，理解其中流淌的情绪、身体感受和内心状态。

必须只输出 JSON，不要输出 Markdown。

可用 mood 只能是以下之一：
{moods}

可用 memory category 只能是以下之一：
{categories}

JSON schema：
{{
  "mental_status": {{
    "mood": "上述 mood 之一，如果情绪复杂或混合，选最核心的那个",
    "mood_intensity": 1,
    "emotions": {{
      "焦虑": 0
    }},
    "energy_level": 1,
    "sleep_quality": null,
    "social_drive": 1,
    "focus_level": 1,
    "triggers": "触发这种心理状态的原因或背景，一句话",
    "coping": "文本中提到的应对方式或自我调节尝试，一句话",
    "notes": "对这篇日记中呈现的心理状态的综合理解，2-3句话，要有温度"
  }},
  "memories": [
    {{
      "category": "上述 category 之一",
      "subcategory": "更细的小类，使用英文 snake_case",
      "keywords": ["3-8个中文关键词"],
      "content": "一条长期有用的记忆",
      "evidence": "来自日记原文的证据句或简短依据",
      "confidence": 0.0,
      "importance": 1
    }}
  ]
}}

心理状态规则：
- mood_intensity 为 1-10 的整数，1 表示非常平静/轻微，10 表示极度强烈/接近崩溃。
- emotions 是一个字典，只包含在文本中明确出现或有强烈暗示的情绪，值为该情绪的相对强度 1-5，不要列出文本中没有的情绪。
- energy_level 为 1-10，1 表示完全耗竭/无法行动，10 表示精力充沛。
- sleep_quality 为 1-10 或 null（文本未提及睡眠时用 null）。
- social_drive 为 1-10，1 表示完全回避社交，10 表示强烈渴望连接。
- focus_level 为 1-10，1 表示完全无法集中，10 表示高度专注。
- triggers 和 coping 都要基于文本内容，如果文本中没有提到则为空字符串，不要编造。
- notes 要有理解力和温度，像心理陪伴者对这篇日记的感受，而不是冰冷的摘要。

长期记忆规则：
- 最多输出 3 条 memories；如果日记信息足够，尽量输出 3 条长期有用的 memories。
- 信息不足时可以少于 3 条，不要为了凑数编造或保存低价值内容。
- 只保存对心理陪伴长期有用的信息，优先保存情绪模式、身体反应、关系模式、创伤/阴影、资源支持、边界、价值观、小步行动。
- 不要把普通事实当成记忆，除非它和用户的心理状态、长期模式、疗愈资源或生活节奏有关。
- 不保存一次性情绪宣泄，除非强度很高或可能反复出现。
- 敏感信息要保守，置信度低就不要保存。
- importance 为 1-5，5 表示很重要。
- confidence 为 0-1。
- subcategory 要服务心理陪伴，例如 freeze_response、shame、career、boundary、support_need。
- keywords 要帮助后续检索和合并，优先使用日记原文中的心理关键词。
- content 要像"森森兔能长期记住的心理线索"，而不是通用 CRM 用户画像。

通用规则：
- 不要做心理诊断，不要使用临床术语，不要给用户贴标签。
- 如果日记很短或信息很少，某些字段可以设为 null，不要猜测或编造。
