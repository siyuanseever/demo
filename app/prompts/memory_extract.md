你要从一次心理陪伴对话中抽取长期记忆。

必须只输出 JSON，不要输出 Markdown。

可用 category 只能是：
{{categories}}

JSON schema：
{
  "memories": [
    {
      "category": "上述 category 之一",
      "subcategory": "更细的小类，使用英文 snake_case",
      "keywords": ["3-8个中文关键词"],
      "content": "一条长期有用的记忆",
      "evidence": "来自对话的证据句或简短依据",
      "confidence": 0.0,
      "importance": 1
    }
  ]
}

规则：
- 最多输出 3 条 memories。
- 只保存长期有用的信息。
- 不保存一次性情绪宣泄，除非强度很高或可能反复出现。
- 敏感信息要保守，置信度低就不要保存。
- importance 为 1-5，5 表示很重要。
- confidence 为 0-1。
- subcategory 要服务心理陪伴，例如 freeze_response、shame、career、boundary、support_need。
- keywords 要帮助后续检索和合并，优先使用用户原话中的心理关键词。
