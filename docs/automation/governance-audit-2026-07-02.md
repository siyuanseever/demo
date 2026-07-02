# 自动化治理审计 — 2026-07-02

## 结论

四 Agent 的角色拆分本身可以保留，但运行时没有真正遵守仓库中的新版 Prompt。当前首要问题不是增加 Agent，而是让协议生效并建立幂等、分支和证据门控。

## 已观察到的问题

| 问题 | 证据 | 风险 | v3 处理 |
|---|---|---|---|
| 新 Prompt 未生效 | 最新 PM coordination 仍为 v1 | 文档与实际行为脱节 | revision 强校验 + 激活 dry run |
| PM 重复运行 | 2026-07-02 有 4 个 PM run | 重复规划、状态覆盖 | `schedule_slot_id` 唯一 |
| PM 下发多个任务 | 多份 coordination 含 3 个 task | Executor 范围失控 | `today_tasks` 只能 0/1 |
| Executor 重复执行 | PM-TASK-004 有两份执行报告 | 重复消耗、结论冲突 | 原子 claim + `task_key` 幂等 |
| 启动结论矛盾 | 一份写待人工验证，一份写启动成功 | 无法信任完成状态 | 证据等级与完成语义 |
| 平台方向被推断 | PM 从代码推断原生 macOS | 可能造成大规模返工 | 固定 Mac Catalyst，方向变化需人工 |
| 错误判断分支状态 | automation 领先被写成分歧/阻塞 | 无意义的 Git 任务 | ancestry 四态分类 |
| PM 提交落到 main | `3998357` 位于 main | 绕过隔离与人工合并 | PM 也强制 worktree preflight |
| Checker cursor 不完整 | state 无 Executor cursor | 回执重复或漏验 | schema v3 强制迁移 |
| JSONL 写入不可靠 | checker index 两条 JSON 曾拼在同一行 | 消费器解析不确定 | 单行校验、换行追加、无效即阻塞 |
| Gate 口径冲突 | 报告同时出现 262/262 与 270/271 | 假稳定 | 同一 commit 建立唯一基线 |

## 产品架构判断

### 当前采用

- Mac Catalyst 是交付平台。
- Python 后端和仓库 `data/app.db` 是既有数据权威源。
- Mac 沙盒 Documents 中的 SQLite 是缓存和离线降级。
- App 通过本机 API 自动刷新：启动、回前台、写入完成和后端恢复。
- 手动刷新保留为故障恢复，不是正常流程。

### 当前不采用

- App 直接持续读写仓库中的活动 `data/app.db`。
- 同时把 Python 和 Swift 两套聊天/总结/记忆逻辑当作权威实现。
- 在稳定化阶段迁移原生 AppKit。

## 激活验收

在以下条件全部成立前，不恢复自动提交：

1. 四个 dry run 都报告 v3 和正确 revision。
2. PM 只产生一个任务。
3. Executor 对重复 task key 明确拒绝。
4. 所有修改发生在 automation worktree。
5. Checker 能消费并独立复验 Executor 报告。
6. main 没有自动化直接提交。

激活步骤见 `activation-checklist.md`。
