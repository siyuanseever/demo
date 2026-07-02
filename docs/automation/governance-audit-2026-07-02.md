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
| 平台方向被推断 | PM 从代码推断当前已是原生 macOS | 可能造成大规模返工 | 明确当前是 Catalyst 迁移版、长期才迁移原生 |
| 错误判断分支状态 | automation 领先被写成分歧/阻塞 | 无意义的 Git 任务 | ancestry 四态分类 |
| PM/main commit 过多 | 多个 `docs(pm)` commit 位于 main | 历史噪声和持续分歧 | PM 改为只读 main、只写 handoff，不再 commit |
| 运行中再次混合提交 | `f425ce1` 把 Web 修复与治理文档一起提交到 main | 单任务和路径边界未生效 | 激活前暂停自动提交，dry run 验证 |
| Checker cursor 不完整 | state 无 Executor cursor | 回执重复或漏验 | schema v3 强制迁移 |
| JSONL 写入不可靠 | checker index 两条 JSON 曾拼在同一行 | 消费器解析不确定 | 单行校验、换行追加、无效即阻塞 |
| Gate 口径冲突 | 报告同时出现 262/262 与 270/271 | 假稳定 | 同一 commit 建立唯一基线 |
| 治理任务派给 Executor | `PM-TASK-009` 要求 Executor 修改 automation/state | 与 Executor 禁止修改协议冲突 | PM 只上报治理事项，由用户/Codex处理 |
| PM/Executor 小时级触发 | PM 已出现 03/13/21/22/23 多轮，Executor 短时间重复运行 | 重复规划、重复消费、token/Git 噪声 | PM 每日一次，Executor 主执行+仅重试 slot |
| Worktree 被 Agent 重建/删除 | 用户观察到固定 worktree 曾被删除并换 branch | 丢失未提交状态、分支漂移 | 四 Agent 禁止全部 worktree/branch 生命周期命令 |

## 产品架构判断

### 新增 Critical 事故

- `MAC-MEM-GROWTH-001`：Mac App 内存持续增长至约 65GB。
- 已确认 `SendInstrumentation.cpuUsage()` 的 `task_threads` Mach allocation 释放地址/size 错误。
- 已识别 heartbeat 在主线程阻塞时缺少 in-flight 背压。
- 处理规范见 `mac-memory-incident-playbook.md`。

### 当前采用

- 当前运行版本是 iOS App 的 Mac Catalyst 迁移版。
- 原生 macOS 是长期方向，按 N0-N5 分阶段迁移。
- Python 后端和仓库 `data/app.db` 是既有数据权威源。
- Mac 沙盒 Documents 中的 SQLite 是缓存和离线降级。
- App 通过本机 API 自动刷新：启动、回前台、写入完成和后端恢复。
- 手动刷新保留为故障恢复，不是正常流程。

### 当前不采用

- App 直接持续读写仓库中的活动 `data/app.db`。
- 同时把 Python 和 Swift 两套聊天/总结/记忆逻辑当作权威实现。
- 在发送卡死尚未取证时，把原生迁移当作默认修复。

## 激活验收

在以下条件全部成立前，不恢复自动提交：

1. 四个 dry run 都报告 v3 和正确 revision。
2. PM 只产生一个任务。
3. Executor 对重复 task key 明确拒绝。
4. 所有修改发生在 automation worktree。
5. Checker 能消费并独立复验 Executor 报告。
6. PM 不产生 Git commit，其他三个 Agent 不向 main 提交。

激活步骤见 `activation-checklist.md`。
