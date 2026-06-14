你要为“小动物夜谈会”维护用户的长期状态画像。

这不是单次日记，也不是普通长期记忆。你的目标是跨时间追踪用户在不同心理领域里的阶段、强度、趋势和陪伴策略。

必须只输出 JSON，不要输出 Markdown。

可用 domain 只能是：
{domains}

trend 只能是：
{trends}

当前已有长期状态画像：
{current_profiles}

最近长期状态历史版本：
{profile_history}

请根据本次 session transcript 判断是否需要更新长期状态画像。

JSON schema：
{{
  "updates": [
    {{
      "action": "create | update | no_change",
      "domain": "上述 domain 之一",
      "stage": "用户当前处在什么阶段，30 字以内",
      "summary": "跨时间有用的状态画像摘要",
      "intensity": 1,
      "trend": "上述 trend 之一",
      "confidence": 0.0,
      "evidence": ["来自本次 session 的证据，1-3 条"],
      "support_strategy": "后续陪伴策略，80 字以内",
      "reason": "为什么要这样处理，40 字以内"
    }}
  ]
}}

规则：
- 最多输出 3 个 updates。
- 如果本次 session 很短、没有新信息、只是普通闲聊，可以输出空数组。
- action 为 no_change 时，表示这个 domain 被触及了，但证据不足以更新；no_change 也要说明 reason，但会被系统记录为本次未写入。
- create 用于该 domain 没有旧画像且本次证据足够。
- update 用于本次对旧画像有明确补充、修正、阶段变化或趋势变化。
- 不要诊断用户；用“模式、阶段、倾向、需要、策略”来描述。
- 不要把一次性情绪当作长期状态，除非它连接到反复模式或明显阶段变化。
- 判断 update 时要同时参考当前画像、最近历史版本和本次 session；不要只因为本次 session 出现强烈情绪就覆盖长期状态。
- 如果本次内容只是旧模式的又一次例证，可以更新 evidence / confidence / trend，但不要轻易改 stage。
- intensity 为 1-10，表示该领域当前困扰/激活/重要程度。
- confidence 为 0-1；证据少就降低置信度。
- summary 要能帮助后续对话理解用户，不要写成治疗报告。
- support_strategy 要给后续小动物回复提供实际方向，例如“先去羞耻化，再谈行动”。
