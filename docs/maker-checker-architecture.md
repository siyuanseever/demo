# Maker / Checker 双 Agent 架构设计

> 当前阶段为方向性设计，实现细节待后续迭代确定。

---

## 1. 角色定义与职责边界

| 角色 | 职责 | 类比 |
|------|------|------|
| **Maker** | 执行具体任务：生成代码、编写 prompt、修改配置、实现功能 | 工程师 / 实现者 |
| **Checker** | 验证 Maker 产出：运行门控、执行测试、评估质量、标记风险 | QA / 审查者 |

**核心原则**：Maker 和 Checker 是**独立运行的 Agent**，各自使用独立的 system prompt、上下文和工具集。Checker 不给 Maker "放水"，Maker 不预判 Checker 的评判标准。

---

## 2. 与现有基础设施的映射

项目已有多处机制天然适合 maker/checker 拆分：

| 现有机制 | Maker 侧 | Checker 侧 |
|---------|---------|-----------|
| **Harness 门控** | 产出代码 / prompt / 配置 | Gate 0-4 自动验证 |
| **Loop 迭代** | `task_executor` 注入业务逻辑 | 验证产出，失败写入 `loop_memory` |
| **Evaluation 框架** | 实现功能 | `runner` / `diagnose` / `manual_eval` |
| **Prompt Inspector** | 编写 / 修改 prompt | 实时追踪 JSON 有效性、token 用量、质量评分 |
| **TODO.md 任务** | 从"进行中"选取并执行 | 完成后自动验证，失败写入 `loop_memory` |

---

## 3. 交互流程

```
TaskSource (TODO.md)
        │
        ▼
┌───────────────┐
│     Maker     │
│               │
│ 1. 读取 plan/status
│ 2. 加载 loop memory
│ 3. 执行具体任务
│ 4. 产出变更（代码/prompt/配置）
└───────┬───────┘
        │
        ▼
┌───────────────┐
│    Checker    │
│               │
│ 1. 判断变更类型
│ 2. 触发对应门控
│    - Python → Gate 0 + Gate 1
│    - web.py → Gate 0 + JS + Gate 1
│    - Prompt → Gate 3 + Gate 4
│    - 新增模块 → Gate 0 + 1 + 2
│ 3. 运行 diagnose（若失败）
│ 4. 输出 verdict
└───────┬───────┘
        │
   ┌────┼────┐
   ▼    ▼    ▼
[通过] [测试缺陷] [产品缺陷]
   │      │        │
   ▼      ▼        ▼
写入    修复测试  修复产品
loop    重跑门控  代码
memory          重跑门控
type=decision
标记完成
```

### Verdict 结构

Checker 输出的 verdict 必须包含以下字段：

```json
{
  "verdict": "pass | test_defect | product_defect | needs_review",
  "gate_results": {
    "gate0_syntax": true,
    "gate1_functional": true,
    "gate2_structure": true,
    "gate3_prompt": null,
    "gate4_experience": null
  },
  "diagnosis": {
    "failed_tests": [],
    "classification": "product_defect | test_defect | unknown",
    "repair_suggestion": ""
  },
  "risk_level": "low | medium | high",
  "notes": ""
}
```

---

## 4. 状态与记忆分离

| 维度 | Maker 关注 | Checker 关注 |
|------|-----------|-------------|
| `plan.md` | 读取阶段目标，对齐执行方向 | 验证产出是否符合验收标准 |
| `status.md` | 读取当前进度，避免重复工作 | 更新验证结果，标记新问题 |
| `loop_state.json` | 读取迭代次数、已完成任务 | 写入验证结果、当前 verdict |
| `loop_memory.jsonl` | 读取历史决策和错误，避免重复踩坑 | 写入本次错误、模式发现、决策记录 |

### 记忆类型约定

| 类型 | 写入者 | 内容 |
|------|--------|------|
| `decision` | Maker | 关键实现决策（为什么这样设计） |
| `observation` | Maker | 执行过程中的发现 |
| `error` | Checker | 验证失败及诊断结果 |
| `pattern` | Checker | 重复出现的问题模式 |

---

## 5. 与 Ralph 技术的兼容性

双 Agent 架构与 Ralph 技术**完全兼容**：

- **每次迭代完全重置上下文**：Maker 和 Checker 各自无状态，所有输入从磁盘读取
- **完成任务后立即退出**：Checker 完成验证后退出，verdict 写入磁盘
- **记忆存储在磁盘**：Maker 的决策和 Checker 的 verdict 都写入 `loop_memory.jsonl`

### 两种运行模式

#### 模式 A：同一次迭代内（串行）

```python
runner = LoopRunner()
# 先 Maker
runner.set_task_executor(maker_executor)
result = runner.run_once()

# 再 Checker（使用新实例，重置上下文）
checker_runner = LoopRunner()
checker_runner.set_task_executor(checker_executor)
verdict = checker_runner.run_once()
```

**适用场景**：单次变更量小，希望快速验证闭环。

#### 模式 B：不同迭代内（异步）

```
迭代 N：Maker 完成任务 → 标记完成 → 退出
迭代 N+1：Checker 启动 → 先验证上次产出 → 输出 verdict → 退出
迭代 N+2：若 verdict 为 product_defect，自动创建修复任务 → Maker 执行
```

**适用场景**：Checker 需要较长时间运行（如完整回归测试），或希望人工审核 verdict。

---

## 6. 与 Worktree 的关系（未来扩展）

当架构进入实现阶段时，Maker 和 Checker 可以在**独立的 Git Worktree** 上运行：

```
项目根目录（main branch）
  ├── .git/worktrees/maker-branch/   ← Maker 工作区
  │      └── app/...（独立修改）
  └── .git/worktrees/checker-branch/ ← Checker 工作区
         └── app/...（独立验证）
```

### Worktree 优势

- **物理隔离**：Maker 和 Checker 同时运行不会互相踩文件
- **独立 Branch**：每个 Agent 在独立的 git branch 上工作
- **安全合并**：最后通过 PR Merge 统一处理冲突
- **回退简单**：若 Checker 发现严重问题，可直接丢弃 Maker 的 branch

### Worktree 工作流程

```
1. Loop 选择任务
2. 为 Maker 创建独立 Worktree + Branch
3. Maker 在隔离环境中执行
4. Maker 提交到 Branch
5. Checker 在另一个 Worktree 中 checkout Maker 的 Branch
6. Checker 运行验证
7. Checker 输出 verdict
8. 若通过 → PR Merge 到 main
9. 若失败 → 诊断 → Maker 修复 → 重新提交 → Checker 重验
```

**当前阶段**：仅在文档中标注此方向，不实现。后续当 Loop 需要支持并行 Agent 时引入。

---

## 7. 未来扩展方向

### 7.1 多 Maker 协作

- 不同 Maker 负责不同模块（如一个负责 prompt，一个负责存储层）
- 需要增加**合并协调者（Merger）**角色，处理多 Maker 的代码冲突

### 7.2 Checker 分级

| 级别 | 职责 | 触发条件 |
|------|------|---------|
| L1 快速检查 | compileall + 单元测试 | 每次迭代 |
| L2 功能检查 | 完整 runner + diagnose | 功能完成后 |
| L3 体验检查 | manual_eval + case 验证 | 重大变更后 |
| L4 安全审查 | 代码漏洞扫描 + 依赖审计 | 发布前 |

### 7.3 人类介入点

以下情况 Loop 应暂停自动运行，等待人类判断：

- Checker verdict 为 `needs_review`（无法自动分类）
- 高风险场景（如安全相关修改）
- Token 预算或迭代次数达到上限
- 连续多次迭代失败（可能陷入死循环）

---

## 8. 与当前代码的集成点

当前无需修改现有代码，但未来实现时需要注意以下集成点：

| 集成点 | 当前状态 | 未来需要 |
|--------|---------|---------|
| `app/loop/runner.py` | `task_executor` 为 Hook，默认返回 dispatched | 注入 Maker 和 Checker 的具体执行逻辑 |
| `app/loop/task_selector.py` | 从 TODO.md 选择任务 | 增加 verdict 驱动的任务优先级调整 |
| `app/loop/memory.py` | 支持 decision/observation/error/pattern | 增加 verdict 类型，支持按 Agent 过滤 |
| `app/web.py` API 路由 | 已有 harness-status / loop-status / loop-memories | 增加 verdict 提交和查询接口 |
| `AGENTS.md` 编排规则 | 变更类型与门控映射 | 增加 Maker/Checker 触发条件 |

---

## 9. 决策记录

| 决策 | 方案 | 原因 |
|------|------|------|
| 当前是否实现 | 只出设计文档 | 用户明确要求当前只做架构方向 |
| 是否修改 Loop 代码 | 不修改 | 现有 Hook 机制已足够支持未来扩展 |
| Worktree 是否现在引入 | 不引入 | 当前单 Agent 运行，无并行冲突 |
| Checker 是否使用不同模型 | 建议不同 | 避免"自己给自己打分"的偏差，可用同一模型的不同 system prompt |
| verdict 是否自动驱动修复 | 建议半自动 | 产品缺陷自动重试，测试缺陷需人工确认测试是否正确 |
