# 自动化 Agent 编排协议

本文件定义 PM、Executor、Checker、Fixer 四个 Agent 的运行时契约。调度器只负责定时、互斥和唤起，不做产品判断，也不作为第五个智能 Agent。

## 1. 当前协议

- 协议：`xiaodongwu-automation/v3`
- Prompt revision：`2026-07-02-governance-1`
- 时区：`Asia/Shanghai`
- 当前运行平台：iOS App 的 Mac Catalyst 迁移版
- 长期平台方向：原生 macOS，按 Roadmap N0-N5 分阶段迁移
- 自动化分支：`automation/quality-loop`
- 自动化 worktree：`/Users/liangsiyuan/.trae-cn/work/6a44adb20787131fb56cfca1/xiaodongwu-quality-loop`
- 主工作区：`/Users/liangsiyuan/work/agent/demo`
- 共享交接目录：`/Users/liangsiyuan/work/agent/demo/eval_reports/agent_handoffs`

任何 Agent 的运行时 Prompt、输入消息或 state 不是 v3/revision 不一致时，必须生成 `protocol_mismatch` 报告并退出，不能“兼容执行”。

## 2. 调度频率

当前处于 P0 incident 模式：

| Agent | 固定时间 | 每个 slot 的工作 |
|---|---|---|
| PM | 01:00 | 每天一次扫描方向和证据，最多下发 1 个任务 |
| Checker | 02:00 | 每日完整增量审查和 Harness |
| Fixer | 04:00、10:00、16:00、22:00 | P0 期间每 6 小时处理一次新 Checker 缺陷 |
| Executor | 06:00 | 原子领取并执行 1 个 PM 任务 |
| Executor retry | 18:00 | 只重试明确 `retryable` 的同一任务，或执行用户批准的紧急任务；不得重复 completed task |
| Checker | 08:00 | 优先复验 Fixer/Executor 回执 |
| Checker | 14:00、20:00 | 有新提交则增量检查；无变化只写轻量 no_change |

`schedule_slot_id` 格式：`<role>-YYYYMMDD-HH`。同一 role + slot 只能成功创建一个 run。发现 slot 已存在时写 `duplicate_slot` 调度记录并退出，不生成第二份正式报告。

稳定模式（`MAC-HANG-SEND-001` 已关闭且连续 7 天无 high issue）：

- PM：每天 1 次；
- Executor：每天 1 次或由新 PM task 事件触发；
- Checker：每 12 小时 1 次；
- Fixer：每天 1 次，无新 product issue 时快速 no-op。

禁止 PM 或 Executor 每小时轮询。小时级运行不会增加有效开发量，只会增加重复报告、stale task、Git 同步和 token 消耗。

高风险问题只通知用户，不临时唤起另一个智能 Agent。需要加跑时，由用户或确定性调度器创建带唯一 slot ID 的一次性任务。

## 3. 激活前提

仓库文件不会自动改变 TRAE/Codex 中已经保存的定时任务 Prompt。每个定时任务必须：

1. 使用对应 Prompt 文件的完整内容，或使用一个只负责读取对应文件并严格执行的 launcher；
2. 在首行固定声明 v3 和 prompt revision；
3. 把实际 `protocol`、`prompt_revision`、`schedule_slot_id` 写入报告；
4. 通过一次 dry run 后才恢复自动提交。

具体步骤见 `docs/automation/activation-checklist.md`。

## 4. 工作区与强制 Preflight

工作区模型：

- PM 在主工作区 `main` 只读运行；所有输出写入已忽略的 handoff，不修改、不暂存、不提交 Git 文件。
- Executor、Checker、Fixer 只在固定 automation worktree/branch 运行。
- worktree 和 automation branch 的创建、删除、修复只归用户或一次性 bootstrap 工具，不归四个 Agent。

四个 Agent 在任何读取队列、修改文件或运行验证之前都必须完成：

1. 获取共享锁 `/private/tmp/xiaodongwu-quality-loop.lock`。
2. 验证当前时间与 `schedule_slot_id` 的偏差不超过 10 分钟；人工 dry run 可使用 `manual-*` slot。
3. 验证 Prompt revision 和输入协议。
4. 验证自己所在的工作区和分支符合角色要求。
5. Executor、Checker、Fixer 执行 Git 关系分类；PM 跳过。
6. 验证自己的 state schema；不匹配时迁移或 `blocked`，不得混用字段。
7. 验证对应 index 每一行都是独立合法 JSON。

Executor、Checker、Fixer 必须在自动化 worktree 中执行：

```bash
test "$(git rev-parse --show-toplevel)" = "/Users/liangsiyuan/.trae-cn/work/6a44adb20787131fb56cfca1/xiaodongwu-quality-loop"
test "$(git branch --show-current)" = "automation/quality-loop"
test -z "$(git status --porcelain)"
```

PM 必须在主工作区执行：

```bash
test "$(git rev-parse --show-toplevel)" = "/Users/liangsiyuan/work/agent/demo"
test "$(git branch --show-current)" = "main"
```

PM 不要求 main 干净，因为它不写 Git 文件；不得执行 `git add`、`git commit`、merge、branch 或 worktree 命令。

Executor、Checker、Fixer 涉及 commit、merge 或 branch 元数据读取时使用共享 Git 锁 `/private/tmp/xiaodongwu-git.lock`。

### Worktree 生命周期保护

四个 Agent 均严格禁止：

- `git worktree add/remove/prune/repair`；
- 创建、删除、重命名 `automation/quality-loop`；
- worktree 缺失时自行选择新路径或新 branch；
- 删除其他 Agent 的 lock、state 或未提交文件。

固定 worktree 不存在、路径不匹配或 branch 不存在时，状态必须为 `worktree_missing`，只生成报告并通知用户。

## 5. Git 关系分类

以 `main` 和 `automation/quality-loop` 的真实 ancestry 分类：

- 两者相同：`equal`，继续。
- `automation/quality-loop` 是 `main` 的祖先：`main_ahead`，在干净 worktree 合并 `main`。
- `main` 是 `automation/quality-loop` 的祖先：`quality_loop_ahead`，这是正常状态，不同步、不报错。
- 两者互不为祖先：`diverged`，停止并请求用户处理。

Git 同步属于确定性 preflight，PM 不得把“合并分支”下发为产品任务。任何 Agent 都不得 push、rebase、force、自动合并回 main 或自动解决冲突。

本节仅适用于 Executor、Checker、Fixer。PM 已在 main 上运行，不执行 main → quality-loop 同步。

## 6. 队列、Index 与 State

目录保持：

```text
eval_reports/agent_handoffs/
├── pm/YYYYMMDD/<run_id>/
├── executor/YYYYMMDD/<run_id>/
├── checker/YYYYMMDD/<run_id>/
├── fixer/YYYYMMDD/<run_id>/
├── indexes/{pm,executor,checker,fixer}_runs.jsonl
├── state/{pm,executor,checker,fixer}_state.json
└── LATEST_{PM,EXECUTOR,CHECKER,FIXER}.json
```

写入顺序：

1. 在 run 目录写临时文件并校验 JSON；
2. 原子 rename 报告；
3. 确保 index 旧文件以换行结尾，再追加一行 JSON 和一个换行；
4. 原子更新 state；
5. 原子更新 `LATEST_*`。

`LATEST_*` 只供人查看，Agent 必须消费 append-only index + cursor。index 任一行无法独立解析时，停止消费并报告 `invalid_index`，不得猜测或跳过。

所有 state 使用 schema version 3，并至少记录：

- `protocol`
- `prompt_revision`
- `last_run_id`
- `processed_run_ids`
- `claimed_task_keys`（仅 Executor）
- `completed_task_keys`（仅 Executor）
- `updated_at`

## 7. PM → Executor

PM 每个 slot 只能生成 0 或 1 个 `today_tasks`。其他建议放入 `backlog_observations`，不能放进可执行数组。

任务必须包含：

- `task_id`：全局唯一，包含 PM run ID；
- `task_key`：`<source_pm_run_id>/<task_id>`；
- `workstream`、`target_platform=mac_catalyst_migrated_ios`、`target_surface`；
- `problem_statement`、`data_source`、`acceptance_criteria`；
- `evidence_required`、`non_goals`、`allowed_paths`；
- `requires_human` 和依赖。

平台迁移、数据权威源变化、安全策略、删除/迁移数据和大范围架构调整必须 `requires_human=true`，不得下发 Executor。

自动化协议、Prompt、state migration、worktree/branch 修复属于治理任务，只能由用户或 Codex 执行。PM 只能写入 `notes_for_human_pm`，不得把它们放进 `today_tasks` 交给 Executor。

Executor 在产生任何副作用前，必须把 `task_key` 原子写入 `claimed_task_keys`。已完成、已有有效 claim 或 source PM run 已处理时，写 `duplicate_task` 并退出。失败时记录明确 disposition，不得通过重复运行制造第二份“完成”报告。

## 8. Checker/Fixer 与产品开发隔离

- Checker 可改测试/Harness，不改产品。
- Fixer 只修 Checker 已稳定复现、契约明确的产品缺陷，不执行 Roadmap 功能。
- Executor 只执行 PM 任务，不写测试。
- PM 只整理方向和证据，不写产品或测试。

Checker 每轮先消费所有未处理的 Executor/Fixer run，再审查新的 commit。只有独立复验后才能关闭 issue 或把 task 标为 `verified`。

若缺少 Apple UI-test target，PM 可以下发一次 `test_infrastructure` 任务，由 Executor 只建立空 target 和必要 project wiring；测试场景、fixture 和断言仍只能由 Checker 编写。

## 9. Mac 专项契约

- 当前运行版本是 Catalyst 迁移版，不得写成原生 macOS App。
- 原生 macOS 是已确认的长期方向，但 N1 以后代码迁移必须满足 Roadmap 门槛；PM 不得把平台重写当作当前卡死的默认修复。
- Python 后端和 `data/app.db` 是当前权威源；Mac 沙盒 SQLite 是缓存。
- Mac App 不直接持续读写仓库的活动数据库文件。
- 自动同步目标是缓存先展示、后台增量刷新、去重/取消/超时、手动刷新兜底。
- 性能任务必须有复现场景、数据规模、trace 和前后对比。
- `xcodebuild` 成功只证明构建；`open App.app` 只证明发起启动。要声称“启动成功且无立即崩溃”，必须提供进程存活或日志证据。
- Python Gate 不能证明 Mac 交互、数据完整性或性能。

### Critical 内存失控

“内存持续增长至约 65GB”按 `MAC-MEM-GROWTH-001` 处理，优先级高于其他产品任务。四个 Agent 必须读取：

`docs/automation/mac-memory-incident-playbook.md`

incident 未经 Checker 关闭前，PM 只能下发内存复现、观测或测试基础设施任务；Executor/Fixer 不得以原生迁移或大范围重构代替证据驱动修复。

### P0 发送卡死

“点击发送后 App 卡死且后端没有收到请求”按 `MAC-HANG-SEND-001` 持续追踪。四个 Agent 必须读取并执行：

`docs/automation/mac-freeze-incident-playbook.md`

在该 issue 被 Checker 独立验证关闭前：

- PM 优先下发观测、复现或测试基础设施任务，不下发低优先级 Roadmap 功能；
- Executor 只能实现任务授权的观测/基础设施，不凭静态阅读宣称修复；
- Checker 负责复现矩阵、测试和 stack/log 证据；
- Fixer 只依据 Checker 的稳定复现和最后成功阶段修产品；
- 原生迁移 N0 可做只读盘点，N1 以后不得用来绕过该 incident。

## 10. 完成语义

- `completed`：全部验收标准和必需证据成立。
- `partial`：完成部分工作，未满足全部验收。
- `pending_manual_validation`：自动证据完成，但仍需人工体验确认。
- `blocked`：缺少环境、权限、方向或合法输入。
- `no_change`：没有新输入或提交。
- `protocol_mismatch` / `duplicate_slot` / `duplicate_task` / `wrong_worktree`：治理拒绝状态。

验证任务发现问题但未修复时，结果是 `partial` 或 `blocked`，不是 `completed`。未经授权的修复不能藏在“验证任务”中。

## 11. 提交边界

- PM：Git 路径白名单为空；只写 handoff。
- Checker：`app/evaluation/**`、专用测试目录和交接报告。
- Fixer：明确 issue 所需的产品文件，不含测试和规划。
- Executor：任务 `allowed_paths` 内的产品文件，不含测试、规划和自动化协议。

一个 commit 只对应一个任务或一个 issue。提交前必须检查 staged path；报告和 commit message 必须准确描述全部变更。

## 12. 治理审计

不增加第五个常驻智能 Agent。由用户或 Codex 每周/方向变化后执行一次只读治理审计，检查：

- 运行时 protocol/revision 是否与仓库一致；
- slot、run、task 是否重复；
- state/index 是否可解析且 cursor 单调；
- 报告结论是否有证据且互相一致；
- Agent 是否越权修改路径、分支或产品方向；
- Roadmap、TODO、plan、status 是否仍与用户目标一致。
