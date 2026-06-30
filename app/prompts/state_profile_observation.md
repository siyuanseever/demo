你要从本次 session 中提取用户的长期心理状态线索。

这是两阶段长期画像更新的第一阶段。此时只观察本次 session，不判断是否覆盖旧画像，也不做心理诊断。

必须只输出 JSON，不要输出 Markdown。

可用 domain 只能是：
{domains}

JSON schema：
{{
  "observations": [
    {{
      "domain": "上述 domain 之一",
      "has_evidence": true,
      "observation": "本次 session 在该领域呈现出的状态、变化或模式",
      "stage_hint": "本次证据提示的阶段，30 字以内",
      "intensity_hint": 1,
      "trend_hint": "上述 trend 之一",
      "confidence": 0.0,
      "evidence": ["本次 session 的直接证据，1-3 条"],
      "support_hint": "这条观察对后续陪伴的提示"
    }}
  ]
}}

规则：
- observations 必须覆盖全部 domain，每个 domain 恰好出现一次，并按给定顺序输出。
- has_evidence=false 时，observation、stage_hint、evidence 和 support_hint 可以为空，confidence 应较低。
- 只提取本次 session 能支持的内容；不要用常识补全，不要因为某个领域名称而猜测。
- 一次性情绪可以作为观察，但要明确它只是当次状态；只有反复模式或阶段变化才是强长期证据。
- evidence 必须能够在本次 session 中找到依据，不要引用旧画像或旧记忆。
- intensity_hint 为 1-10；trend_hint 只能是：{trends}。
- 不要诊断用户；使用“状态、模式、倾向、需要、变化”等描述。
