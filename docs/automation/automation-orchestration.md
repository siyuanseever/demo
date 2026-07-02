# 自动化 Agent 编排

本文件定义调度和队列规则。它不是第三个智能 Agent；调度器只负责定时、互斥、传递 run ID 和维护 cursor，不做代码判断。

## 推荐频率

时区统一为 `Asia/Shanghai`：

| 任务 | 时间 | 说明 |
|---|---|---|
| PM | 01:00 | 每日扫描项目、核对 Mac 主线、生成一项协调指令 |
| Checker | 02:00、08:00、14:00、20:00 | 每 6 小时增量审查、写测试、运行可用 Harness |
| Fixer | 05:00 | 每天批量消费上次 Fixer 之后的所有 Checker run |
| Executor | 06:00 | 读取 PM 协调指令、执行开发任务、提交产品代码 |

调度逻辑：
- 01:00 PM 生成晨间报告和今日任务规划
- 02:00 Checker 进行常规质量检查（验证前一天修改）
- 05:00 Fixer 批量修复 Checker 发现的问题
- 06:00 Executor 读取 PM 协调指令并执行开发任务
- 08:00 Checker 验证 Executor 的修改

这样 Fixer 每次通常消费前一天 08:00、14:00、20:00 和当天 02:00 四轮结果；08:00 Checker 会优先验证 05:00 Fixer 的修复和 06:00 Executor 的提交。

高风险 issue 可以立即通知用户，但默认不额外触发 Fixer，避免并发修改。若以后需要紧急修复，应由确定性调度器增加一次性 Fixer 任务，而不是新增第三个 LLM Agent。

## 持久集成分支

自动化使用一个串行分支和一个固定 worktree：

- branch：`automation/quality-loop`
- worktree：`/Users/liangsiyuan/.trae-cn/work/6a44adb20787131fb56cfca1/xiaodongwu-quality-loop`（在 TRAE 操作白名单内）

Checker、Fixer、PM 和 Executor 轮流在该分支提交。当前产品方向以 `ROADMAP.md` 和 `plan.md` 中的 Mac 主线为准；自动化 Agent 不得自行切回 Web 主线或扩展新的产品方向。

```text
产品基线
  → PM 规划文档 commit（status.md、TODO.md）
  → Checker 测试 commit
  → Checker 测试 commit
  → Fixer 产品 commit
  → Executor 产品 commit（按 PM 协调指令开发）
  → Checker 复验/测试 commit
```

角色隔离由每个 commit 的路径白名单保证，而不是为每轮创建互不相连的 branch。这样一天四轮测试不会产生四条无法汇合的分支。

各 Agent 的 commit 路径白名单：
- PM：`status.md`、`TODO.md`（人类可读规划文档）
- Checker：`app/evaluation/**`、`eval_reports/agent_handoffs/**`
- Fixer：`app/**`（不含 evaluation）、`ios/**`、`docs/**`（不含 automation 协议和规划文档）
- Executor：`app/**`（不含 evaluation）、`ios/**`、`docs/**`（不含 automation 协议和规划文档）

### 合并到 main

所有自动化 Agent（PM、Executor、Checker、Fixer）都**不合并到 main、不 push**。合并由用户手动执行：

```bash
# 在主工作区
git merge automation/quality-loop --no-ff
```

同步主分支（main → quality-loop）时只允许：
- 自动化 worktree 干净
- 能够 fast-forward 或由用户批准普通 merge
- 出现冲突时停止并报告，不自动 rebase、不覆盖用户修改

## 互斥

调度器启动任务前获取共享锁；锁已存在时，本轮写入 `skipped_due_to_lock` 调度记录并退出。

- **共享 worktree 锁**：`/private/tmp/xiaodongwu-quality-loop.lock`
  - 共享者：PM、Checker、Fixer、Executor
  - 四者会在同一分支/worktree 读写或提交，全部必须互斥。文件类型不同不代表 Git index、HEAD 和 merge 操作可以安全并发。

锁必须包含启动时间、任务类型和进程标识，并设置陈旧锁处理策略（30 分钟过期）。Agent 自己不得强行删除无法确认归属的锁。

## 目录和队列

```text
eval_reports/agent_handoffs/
├── pm/
│   └── YYYYMMDD/<pm_run_id>/
├── executor/
│   └── YYYYMMDD/<executor_run_id>/
├── checker/
│   └── YYYYMMDD/<checker_run_id>/
├── fixer/
│   └── YYYYMMDD/<fixer_run_id>/
├── indexes/
│   ├── pm_runs.jsonl
│   ├── executor_runs.jsonl
│   ├── checker_runs.jsonl
│   └── fixer_runs.jsonl
├── state/
│   ├── pm_state.json
│   ├── executor_state.json
│   ├── checker_state.json
│   └── fixer_state.json
├── LATEST_PM.json
├── LATEST_EXECUTOR.json
├── LATEST_CHECKER.json
└── LATEST_FIXER.json
```

索引采用 append-only JSONL，每行只存元数据和报告路径，不复制完整报告。写报告顺序：

1. 在 run 目录写临时文件；
2. 原子 rename 为最终报告；
3. append 对应 index；
4. 原子更新角色自己的 state；
5. 原子更新 `LATEST_*`。

`LATEST_*` 只供人快速查看，不能作为自动消费队列。

## Cursor 规则

PM 拥有：
- `last_pm_run_id`
- `last_requirements_commit`
- `executor_tasks_issued`

Executor 拥有：
- `last_executor_run_id`
- `processed_pm_run_ids`
- `completed_task_ids`

Checker 拥有：
- `last_reviewed_commit`
- `processed_fixer_run_ids`
- `processed_executor_run_ids`
- `last_checker_run_id`

Fixer 拥有：
- `processed_checker_run_ids`
- `last_fixer_run_id`

### 消费关系

- Executor 每天读取 `pm_runs.jsonl`，选择所有不在 `processed_pm_run_ids` 中的合法 run。所有被扫描的 run——包括 `no_change` 和无可执行任务——都必须进入 processed 列表，避免第二天重复读取。
- Fixer 每天读取 `checker_runs.jsonl`，选择所有不在 `processed_checker_run_ids` 中的合法 run。所有被扫描的 run——包括 `no_change` 和 `no_issues`——都必须进入 processed 列表，避免第二天重复读取。
- Checker 每轮读取 `fixer_runs.jsonl`，只验证不在 `processed_fixer_run_ids` 中的 Fixer batch。验证完成后才推进 cursor。
- Checker 每轮读取 `executor_runs.jsonl`，只验证不在 `processed_executor_run_ids` 中的 Executor batch。验证完成后才推进 cursor。

## Fixer 批处理

Fixer 将多轮 Checker 报告合并为一个 batch：

1. 按 `issue_id` 聚合；
2. 同一 issue 只处理一次；
3. 使用生成时间最新的状态和证据；
4. 保留所有 `source_checker_run_ids`；
5. 最新状态为 `resolved`、`observation` 或 `needs_human` 时，不自动修产品；
6. 多个 issue 共享根因时可以一次修复，但必须逐项回执。

Fixer 完成后，一次性把本批次所有已扫描 Checker run 写入自己的 processed cursor。若任务中途失败，不推进 cursor，下次安全重试。

## Executor 任务执行

Executor 读取单份 PM 协调指令（而非多份聚合）：

1. 读取 `coordination.json` 中的 `today_tasks` 列表
2. 按 `priority` 排序，跳过 `forbidden=true` 的任务
3. 验证 `dependencies` 是否已满足（检查 `completed_task_ids`）
4. 当前 Mac 阶段每次最多执行 1 个任务，保持变更范围和验收证据可控
5. 按变更平台执行对应门控；Python Gate 不能替代 Xcode/Mac 验证
6. 一个任务一个 commit
7. 完成后一次性把该 PM run 写入 `processed_pm_run_ids`

若任务中途失败，已完成的任务推进 cursor，失败的任务记录 blocker 并留待下次处理。

## PM 协调规则

PM 每天生成一份报告和协调指令：

1. 扫描项目状态后不直接消费任何 Agent 报告，只做只读分析
2. `coordination.json` 中的 `today_tasks` 必须对应同一 run 的 `pm_report.md` 具体章节
3. 任务粒度控制：小任务（<50 行变更）、中任务（50-200 行）、大任务（>200 行）需拆分为多个小任务
4. 涉及安全策略、危机回复、架构方向变更的任务必须标记 `forbidden=true` 并附 `reason_if_forbidden`
5. PM 的 `no_change` 报告仍需生成，用于记录"今日无新任务"状态
6. 当前每天最多下发 1 个 Mac 任务，且必须包含 `workstream`、`target_surface`、`data_source`、`non_goals`、`acceptance_criteria` 和 `evidence_required`
7. PM 只能依据用户已经确认的 `ROADMAP.md` / `plan.md` 排序和拆解，不得自行修改战略方向

## Mac 阶段验证规则

- Swift/Mac 改动必须记录 Xcode 或 `xcodebuild` 的 target、命令和退出码。
- 性能任务必须记录复现场景、数据规模、修改前后证据；“感觉更快”不是完成证据。
- 数据展示任务必须提供 `SQLite/API → model → store → view` 映射和完整/缺失数据场景。
- 心流与夜谈任务必须验证触发规则、每屏上限、点击路径、来源/更新时间、空状态和返回路径。
- 自动化环境没有 Xcode、目标 Mac 或性能工具时，相关任务状态只能是 `blocked` 或 `pending_manual_validation`。
- Python `compileall` / evaluation runner 仅验证后端兼容性，不得用于宣称 Mac 构建、交互或性能通过。

## 报告层次

- PM：每天一份 run 报告 + 协调指令，是当日的产品规划基线和任务分配依据。
- Executor：每天一份执行报告，记录已完成的任务、变更文件和验证结果。
- Checker：每 6 小时一份 run 报告，用于追踪增量和独立复验。
- Fixer：每天一份 batch 回执，是当天给用户和下一轮 Checker 的聚合摘要。
- 不要求第五个 Agent 再生成日报；PM 的 Markdown 报告即每日产品日报，Executor 报告即每日开发日报。
