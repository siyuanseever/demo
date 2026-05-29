# 记忆分类

MVP 阶段只使用 8 类一级记忆：

- `self_core`：身份、价值观、能量来源、边界。
- `emotion_pattern`：常见情绪、触发点、调节方式。
- `body_response`：冻结、疲惫、紧张、睡眠、躯体化线索。
- `relationship_pattern`：重要他人、亲密关系、工作关系、家庭关系。
- `trauma_shadow`：羞耻、恐惧、被抛弃感、长期压抑。
- `resource_support`：让用户恢复力量的人、事、地点、活动。
- `life_habit`：作息、饮食、运动、工作节奏。
- `goal_action`：近期愿望、阻碍、小步尝试。

每条记忆还包含：

- `subcategory`：更细的小类，例如 `freeze_response`、`shame`、`career`。
- `keywords`：3-8 个中文关键词，用于后续检索、合并和回顾。
- `status`：`active`、`merged`、`contradicted`、`archived`。

会话结束后的记忆流程：

1. 从对话中抽取 0-3 条候选记忆。
2. 按 category、subcategory、keywords 找旧记忆候选。
3. 判断 `create / merge / update / contradict / ignore`。
4. 只把长期有用的内容写入或更新到 memories 表。
