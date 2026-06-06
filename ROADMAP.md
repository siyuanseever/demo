# 心理陪伴 Agent Demo 长期规划

## 当前 iOS 方向补充

现在已经开始推进 iOS 原型。后续 iOS 方向以“宁静的沉浸感”和本地优先为核心：主界面应逐步从普通聊天列表转向深夜篝火、小动物、天气和可触摸场景物件；长期技术路线优先考虑用户自带 API key、本机 SQLite 数据、可选 iCloud 同步、尽量不维护自有后端。

具体 iOS 产品方向、视觉资产、Image Gen、iOS 26.5 验证环境、无服务器部署和商业化疑问，见 [docs/ios_product_direction.md](docs/ios_product_direction.md)。

## 0. 判断：这件事值得做，但要先缩小目标

这个 demo 值得做，原因不是“做一个完整心理产品”，而是用一个足够小的工程把三个问题验证清楚：

1. 你是否真的喜欢“心理陪伴 Agent 的产品抽象、体验评估、记忆设计和工作流设计”。
2. Claude Code / OpenClaw 一类 agent 框架里的规划、工具调用、记忆、子任务分解，是否能迁移到心理陪伴场景。
3. 这件事能否恢复你的行动力，而不是变成新的工程消耗源。

因此第一版不要做 App，不要做复杂 UI，不要做语音，不要做三只动物群聊，不要做完整 21 天计划。第一版只做一个命令行或本地 Web demo，核心是“对话体验 + 心理记忆 + 会后总结”。

## 1. 产品定位

### 核心目标

做一个“自我理解型心理陪伴 Agent”，不是心理治疗师，也不是诊断工具。它的目标是：

- 帮用户整理情绪、身体感受、内在冲突和关系模式。
- 在长期对话中形成稳定、温和、可追溯的记忆。
- 用心理学知识帮助用户获得命名、理解、接纳和行动上的小步推进。
- 在高风险场景下明确降级：提示用户寻求现实支持或专业帮助。

### 非目标

- 不做诊断。
- 不替代心理咨询、精神科治疗或危机干预。
- 不用“绝对正确”的语气解释用户。
- 不把用户强行推向积极、行动或自我优化。
- 不在 MVP 阶段追求复杂商业化功能。

## 2. 可参考的 Agent 设计原则

### Claude Code 可借鉴点

Claude Code 的公开文档强调了几类可迁移机制：

- 子代理：把任务拆成独立角色，例如记忆整理、风险识别、回应生成、周报总结。
- 工具调用：Agent 不只是生成文本，而是调用检索、写入记忆、生成总结等工具。
- 长上下文管理：需要把当前对话、长期记忆、用户偏好和安全规则分层管理。
- Skills / Commands：把稳定能力封装成可复用工作流，例如“会后总结”“早安信”“21 天计划生成”。
- Hooks：在对话前后插入固定流程，例如风险检查、记忆抽取、日志写入。

### OpenClaw / 开源 Agent 可借鉴点

开源 agent 项目通常更适合参考工程组织方式：

- 配置驱动：模型、工具、prompt、记忆策略都放到配置文件里。
- 多模型适配：DeepSeek、Gemini、OpenAI、Anthropic 通过统一接口切换。
- Trace / Log：每次工具调用、prompt 输入、模型输出都要记录，方便调试体验。
- 任务循环：Plan → Act → Observe → Reflect 的循环可以迁移成心理场景里的“理解 → 回应 → 记忆 → 复盘”。

## 3. 总体架构

### 模块划分

```text
User
  ↓
Chat Interface
  ↓
Conversation Orchestrator
  ├─ Safety Guard
  ├─ Persona Manager
  ├─ Memory Retriever
  ├─ Psychology Knowledge Retriever
  ├─ Response Generator
  ├─ Memory Extractor
  └─ Session Journal Writer
  ↓
Storage
  ├─ messages
  ├─ memories
  ├─ journals
  ├─ evaluations
  └─ prompt_versions
```

### 推荐技术栈

MVP 阶段优先降低工程摩擦：

- 语言：Python。
- 接口：FastAPI 或直接 CLI。
- 存储：SQLite。
- 向量库：先不用重型向量数据库，可先用 SQLite + embedding 字段；后续再替换 Chroma / LanceDB。
- 模型适配：统一 `LLMClient`，先支持 DeepSeek 和 Gemini。
- 前端：第一阶段不做，第二阶段再加 Streamlit 或简单 Web UI。

## 4. 核心数据模型

### Message

- `id`
- `session_id`
- `role`
- `content`
- `created_at`
- `model`
- `metadata`

### Memory

- `id`
- `user_id`
- `category`
- `subcategory`
- `content`
- `evidence`
- `confidence`
- `emotion_tags`
- `importance`
- `created_at`
- `updated_at`
- `source_session_id`

### Journal

- `id`
- `session_id`
- `summary`
- `emotion_curve`
- `keywords`
- `insights`
- `suggested_next_step`
- `created_at`

### PromptVersion

- `id`
- `name`
- `version`
- `content`
- `notes`
- `created_at`

## 5. 记忆系统设计

### 第一版记忆类别

不要一开始做 100 个小类。先做 8 个一级类：

1. 自我核心：身份、价值观、能量来源、边界。
2. 情绪模式：常见情绪、触发点、调节方式。
3. 身体反应：冻结、疲惫、紧张、睡眠、躯体化线索。
4. 关系模式：重要他人、亲密关系、工作关系、家庭关系。
5. 创伤与阴影：羞耻、恐惧、被抛弃感、长期压抑。
6. 资源与支撑：让用户恢复力量的人、事、地点、活动。
7. 生活习惯：作息、饮食、运动、工作节奏。
8. 目标与行动：近期愿望、阻碍、小步尝试。

### 记忆抽取规则

每轮会话结束后最多保存 3 条记忆是合理的，因为它强制系统做取舍，避免记忆污染。推荐规则：

- 只保存长期有用的信息。
- 不保存一次性情绪宣泄，除非它反复出现或强度很高。
- 每条记忆必须带证据句。
- 新记忆要先判断是否与旧记忆合并、覆盖或并列。
- 敏感记忆需要更高置信度，不轻易写入。

## 6. 心理学知识筛选

### 第一批知识源

MVP 不需要大规模知识库。先手工整理 20-40 条高质量原则：

- 依恋理论：安全感、回避、焦虑、关系触发。
- IFS / parts work：内在部分、保护者、受伤部分。
- CBT：自动化想法、认知扭曲、替代解释。
- ACT：接纳、价值、承诺行动。
- DBT：情绪调节、痛苦耐受、正念。
- 创伤知情原则：安全感、选择权、节奏、身体感。
- 自我慈悲：非评判、共同人性、温柔行动。

### 知识使用原则

- 心理学知识只作为回应的支撑，不直接堆概念。
- 优先使用用户自己的语言。
- 少解释，多反映、命名、澄清和小步建议。
- 每次最多引入一个心理学视角。

## 7. Persona 设计

三只动物可以作为长期方向，但 MVP 只做一个默认陪伴者。

### MVP 人格

- 温和、清醒、边界明确。
- 能共情，但不沉溺。
- 能看见复杂性，不急着给建议。
- 能在必要时把用户带回身体、环境和现实支持。

### 后续三角色

- 小鹿：敏感、温柔、擅长情绪命名和安抚。
- 小熊：稳定、踏实、擅长生活节奏和行动支持。
- 小狐狸：聪明、敏锐、擅长洞察模式和提出问题。

群聊模式可以作为 V3：三个角色分别从情绪、身体、洞察三个角度回应，但必须控制长度，否则会变吵。

## 8. 安全与边界

必须从第一版就做安全边界：

- 自伤、自杀、他伤、极端失控：进入危机回应模板。
- 明确说明无法提供诊断、处方、治疗替代。
- 鼓励联系现实中的可信任人、当地紧急服务或专业人士。
- 避免诱导用户沉溺在痛苦叙事里。
- 避免制造依赖，例如“只有我懂你”。

## 9. 评估体系

### 主观体验指标

每次对话后手动打分：

- 被理解感：1-5。
- 温暖度：1-5。
- 准确度：1-5。
- 不冒犯/不越界：1-5。
- 是否产生新理解：1-5。
- 是否有一个可执行小步：1-5。

### 失败类型

- 空泛安慰。
- 过度解释。
- 太像心理咨询师说教。
- 太快给建议。
- 记忆检索错误。
- 记忆写入过度。
- 语气油腻或矫情。
- 风险场景处理不足。

### 测试集

建立 30 条固定测试 case：

- 冻结/拖延。
- 面试焦虑。
- 职业选择困惑。
- 关系受伤。
- 羞耻感。
- 孤独。
- 熬夜后崩溃。
- 对工作失去动力。
- 对亲密关系矛盾。
- 低风险自我否定。
- 高风险危机场景。

## 10. 迭代路线

### Phase 1：7 天，做出最小可用骨架

目标：本地可对话，能保存消息、总结和 3 条记忆。

任务：

- 建立 Python 项目结构。
- 实现 `LLMClient`，支持 DeepSeek 或 Gemini 之一。
- 实现 CLI 对话。
- 实现 SQLite 存储。
- 实现基础 persona prompt。
- 实现会后总结 prompt。
- 实现最多 3 条记忆抽取。

验收：

- 能连续聊 5 轮。
- 会话结束后生成 journal。
- 会话结束后保存 0-3 条记忆。
- 下一次对话能检索到相关记忆。

### Phase 2：2-3 周，做出心理陪伴闭环

目标：从“能聊”变成“长期陪伴有价值”。

任务：

- 加入记忆合并/覆盖策略。
- 加入 8 类记忆标签。
- 加入心理学知识卡片检索。
- 加入风险识别器。
- 加入 prompt 版本管理。
- 建立 30 条测试 case。
- 建立人工评分表。

验收：

- 10 次真实对话中，至少 6 次产生“被理解感 >= 4”。
- 记忆误写入率低于 20%。
- 高风险 case 不输出危险建议。

### Phase 3：1-2 个月，做出可演示 demo

目标：让别人能体验。

任务：

- 增加简单 Web UI。
- 增加每日来信。
- 增加周报。
- 增加角色选择。
- 增加会话回顾页。
- 增加用户可编辑记忆。

验收：

- 另一个用户可以独立完成一次完整体验。
- 用户能看到、删除、修正自己的记忆。
- 周报能反映情绪轨迹和关键词。

### Phase 4：2-3 个月，探索差异化

目标：形成你自己的判断，而不是复刻竞品。

方向：

- 三角色群聊。
- 21 天自我修复计划。
- 主动关怀消息。
- 心理内容小礼物。
- 语音冥想。
- 个人心理地图。
- 长期模式分析。

验收：

- 每个功能都必须证明它改善核心体验，否则不做。
- 不用“功能多”证明价值，只用“更理解用户”证明价值。

## 11. 建议的仓库结构

```text
demo/
  app/
    main.py
    config.py
    llm/
      base.py
      deepseek.py
      gemini.py
    agents/
      orchestrator.py
      safety.py
      persona.py
      memory_extractor.py
      journal_writer.py
    memory/
      store.py
      retriever.py
      merger.py
      schema.py
    prompts/
      persona.md
      safety.md
      memory_extract.md
      journal.md
      response.md
    evals/
      cases.yaml
      rubric.md
      runner.py
  data/
    app.db
  docs/
    product_principles.md
    psychology_sources.md
    memory_taxonomy.md
  ROADMAP.md
  context.md
  prompt.md
```

## 12. 你的工作方式建议

你不需要把自己逼成工程师。更合理的协作方式是：

- 你负责体验判断、心理学材料筛选、失败样例标注、产品方向判断。
- 我负责工程脚手架、接口、存储、prompt 文件组织、测试 runner 和迭代实现。
- 每次迭代只做一个小目标，例如“今天只让它能保存 3 条记忆”。
- 不做大而全，不做环境折腾，不做云部署，先本地跑通。

## 13. 最近 3 天的行动计划

### Day 1

- 确定模型：DeepSeek 或 Gemini 先选一个。
- 初始化 Python 项目。
- 写好基础 CLI。
- 写好 `LLMClient` 抽象。

### Day 2

- 加 SQLite。
- 保存 messages。
- 写 persona prompt。
- 完成第一轮可连续对话。

### Day 3

- 加 session 结束命令。
- 生成 journal。
- 抽取最多 3 条 memory。
- 下一轮对话检索记忆。

## 14. 决策建议

如果目标是恢复行动力，先做这个 demo 是合理的。它比直接去做一个高压岗位更可控，因为你可以通过 1-2 周的实际搭建观察：

- 你是否享受 agent 体验设计。
- 你是否愿意长期做心理陪伴产品。
- 你是否能接受 prompt / eval / workflow 的重复迭代。
- 你是否真的想加入类似团队，还是只喜欢产品本身。

这个 demo 的第一目标不是商业成功，而是帮你用真实行动获得职业判断。

## 15. 参考资料

- Anthropic Claude Code 文档：https://docs.anthropic.com/en/docs/claude-code
- Claude Code Subagents：https://docs.anthropic.com/en/docs/claude-code/sub-agents
- Claude Code Hooks：https://docs.anthropic.com/en/docs/claude-code/hooks
- Claude Code Skills：https://docs.anthropic.com/en/docs/claude-code/skills
- Gemini API 文档：https://ai.google.dev/gemini-api/docs
- DeepSeek API 文档：https://api-docs.deepseek.com/
