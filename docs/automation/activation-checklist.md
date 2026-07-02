# 自动化 v3 激活清单

仅修改仓库中的 Prompt 文件不会自动更新 TRAE/Codex 已保存的定时任务。必须完成以下步骤，v3 才算生效。

## 1. 暂停自动提交

先暂停 PM、Executor、Checker、Fixer 的定时自动提交，保留只读 dry run。

## 2. 更新四个定时任务

分别把以下文件的完整内容设置为对应任务 Prompt：

- `docs/automation/product-manager-agent-prompt.md`
- `docs/automation/executor-agent-prompt.md`
- `docs/automation/checker-agent-prompt.md`
- `docs/automation/product-fixer-agent-prompt.md`

四个 Prompt 都会继续读取：

- `docs/automation/automation-orchestration.md`
- `docs/automation/mac-freeze-incident-playbook.md`
- `docs/automation/mac-memory-incident-playbook.md`

如果定时工具支持从文件加载，可使用最小 launcher：

```text
读取并严格执行 <绝对 Prompt 路径> 的完整内容。
运行时协议必须是 xiaodongwu-automation/v3，
prompt_revision 必须是 2026-07-02-governance-1。
不允许沿用定时任务中更旧的内嵌规则。
```

## 3. 清理旧 slot，不删除历史

- 保留既有报告作为审计证据。
- 不复用旧 run ID 或 task ID。
- 将旧 v1/v2 state 备份后迁移为 schema v3。
- 修复 JSONL 缺少换行的问题，但不改写历史记录内容。
- `completed_task_keys` 至少纳入已经执行过的 PM-TASK-M0-001 和 PM-TASK-004，防止重跑。

## 4. 四次 dry run

按 PM → Executor → Checker → Fixer 顺序，各运行一次 `manual-*` slot。必须确认：

- 报告包含正确 protocol 和 prompt revision；
- PM 的 cwd/branch 是主工作区 `main`；
- Executor、Checker、Fixer 的 cwd/branch 是固定 automation worktree / `automation/quality-loop`；
- PM 输出 0 或 1 个任务；
- Executor 能拒绝重复 task key；
- Checker 能消费 Executor run；
- PM 按 `MAC-MEM-GROWTH-001` > `MAC-HANG-SEND-001` > 普通功能排序；
- Fixer 在没有产品 issue 时不修改代码；
- PM 没有修改、暂存或提交任何 Git 文件；
- 其他三个 Agent 没有 commit 落到 main；
- worktree 缺失模拟会得到 `worktree_missing`，不会创建 branch/worktree。

## 5. 恢复调度

dry run 全部通过后，再按编排协议恢复固定时间。首日重点查看 01:00、06:00、08:00 三个 slot 是否形成一次且仅一次的 PM → Executor → Checker 链路。

当前 P0 调度应设置为：

- PM：每日 01:00；
- Executor：每日 06:00，18:00 仅 retryable/人工紧急任务；
- Checker：02:00、08:00、14:00、20:00；
- Fixer：04:00、10:00、16:00、22:00。

删除 PM/Executor 的每小时触发规则，避免同一任务被不同 slot 重复包装或执行。
