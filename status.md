# 当前进度状态

> 人维护的结构化进度视图。
> 最后更新时间：2026-07-06（Mac 双阶段回复卡死止血）

---

## 当前阶段

G0 自动化治理止血 + Mac Catalyst M0 基线与数据架构。

当前运行版本是 iOS App 的 Mac Catalyst 迁移版，并非原生 macOS App。Web/Python 是权威数据和智能能力基础，Mac 沙盒 SQLite 是界面缓存。长期方向是分阶段迁移原生 macOS，但当前先处理可复现卡死。

---

## 自动化实际状态

当前不是"正常运行"，而是 **协议切换未生效**：

- 仓库 Prompt 已升级为 v3（`2026-07-02-governance-1`），但仍需按激活清单更新实际定时任务。
- Checker 最新运行（2026-07-04 19:00）：Python Gate 1 通过（262/262, 100%），确认 MEM-001/MEM-002/SSE 缓冲区修复已合入 `d506635`。
- Checker 成功执行了 fast-forward merge，将 `automation/quality-loop` 与 `main` 对齐到 `d506635`。
- 三个待处理 issue：CHK-GIT-DIVERGED-001 resolved、CHK-EXECUTOR-DUPLICATE-001（Executor 重复执行 PM-TASK-004）、CHK-INDEX-FORMAT-001（checker_runs.jsonl 换行缺失）。
- Fixer 最新运行（2026-07-03 13:02）：worktree_missing——从错误路径 `/Users/liangsiyuan/.codex/worktrees/161b/demo` (detached HEAD) 运行，无产出。
- Checker worktree 仍有未提交的 `test_code_review_findings.py`。
- `executor_state.json` 中 `claimed_task_keys` 为空但 `completed_task_keys` 有值——claim 原子性可疑。
- PM 本日下发 1 个可执行任务（PM-TASK-012：发送路径可观测性），其他为 backlog 建议和 human note。

Git 当前真实状态：`automation/quality-loop` 与 `main` 均指向 `d506635`，分歧已通过 Checker fast-forward merge 解决。

---

## 产品工程基线

### Python / Web

- 最近报告的 Gate 结果存在 262/262 与 270/271 两种口径，需要 Checker 在同一 commit 上重新建立唯一基线。
- `sync_token_empty_bypass_risk` 在不同报告中被同时写为已修复和仍失败，当前不得宣称 Gate 稳定。

### Mac Catalyst

| 指标 | 当前状态 |
|---|---|
| Catalyst 构建 | 本机 Debug Catalyst 构建通过；补齐遗漏的 `SendInstrumentation.swift` target membership |
| 启动持续存活/核心页面 | 本机启动持续 8 分钟以上；夜谈、心流页面可达 |
| 卡死复现与性能 trace | 未完成 |
| 快速回复后等待深度回复卡死 | `fixed_pending_verification`：Mac 使用精简 SSE、跳过重复 final 解码，并取消回复后立即全量同步 |
| 单条消息发送后卡死、后端无请求 | P0，仍需按独立复现场景验证 |
| 内存持续增长至约 65GB | `fixed_pending_verification`：已修 MEM-001/MEM-002 和 SSE 1MB 上限，等待发送/同步/20 分钟 soak 独立复验 |
| 自动刷新 | 当前 `syncIfNeeded()` 不执行同步，仍依赖手动刷新 |
| 数据权威边界 | 已在规划中确认，尚未实现验收 |
| 字段矩阵 | 未完成 |
| 记忆二级目录/叶节点详情 | 未完成 |
| 最近更新日记/记忆入口 | 未完成 |
| 心流单卡片轻互动 | 部分 UI 存在，完整交互未验收 |

---

## 当前 P0

1. 对 Mac 双阶段发送执行连续 10 轮真实发送，确认快速回复、深度回复、界面响应和 correlation ID 完整。
2. Checker 对 `30c0d36` 前后执行内存 A/B，并复验 `MAC-MEM-GROWTH-001` 修复。
3. 完成真实发送、离线后端、页面切换、同步和 20 分钟 soak；2GB 自动止损。
4. 让实际定时任务加载 v3 Prompt，并用一次 dry run 证明协议、分支、cwd 和单任务约束。
5. 停止 PM/Executor 小时级轮询，按 P0 调度表错峰运行。
6. 验证 PM 没有任何 Git 写操作，以及三个代码 Agent 的固定 worktree 保护。
7. Checker 在同一 automation HEAD 上复核 Catalyst 构建、Python Gate 和 Executor 证据。
8. 建立卡死复现场景和六条关键路径性能基线。
9. 为发送路径建立脱敏阶段事件、correlation ID、UI heartbeat 和 hang 采样方案。
10. 完成自动刷新触发矩阵与数据字段矩阵。
11. 按一级类别 → 二级类别 → 叶节点详情核对长期记忆导航。
12. 核对最近更新记忆/日记和三篇关联日记的可见性。

### 2026-07-04 PM 日报要点

- **Python Gate**: 262/262, 100%（Checker 2026-07-04 确认）
- **内存修复确认**: MEM-001/MEM-002/SSE 缓冲区修复已在 `d506635` 合入，等 Mac 环境独立复验
- **已下发任务**: PM-TASK-012（发送路径可观测性：阶段事件 + correlation ID + UI heartbeat）→ 待 Executor 在 2026-07-05 06:00 slot 执行
- **需用户操作**: 定时任务 v3 Prompt 激活、Fixer worktree 修复
- **产品修复阻断**: 两个 P0 事故均因无 Mac 端可观测性而无法推进验证

### 2026-07-03 内存止血证据

- 空闲 116 秒 RSS：约 `104 MB → 69 MB`，未出现持续单调增长。
- `vmmap`：physical footprint `41.8 MB`，peak `92.0 MB`。
- memgraph：192 个系统 `NSXPCConnection/AppIntents` 泄漏，共约 `9.4 KB`；未发现 App 自有类型泄漏。
- heartbeat 压力程序连续 5 次阻塞主线程，每次 pending tick 上限为 `1`，恢复后回到 `0`。
- 尚缺真实 UI 发送、自动同步和 20 分钟 soak，因此 incident 不关闭。

---

## 已确认的产品方向

- 当前实现：Mac Catalyst 迁移版；长期方向：原生 macOS 分阶段迁移。
- 数据：Python 后端为权威源；Mac 沙盒数据库为缓存。
- 同步：启动、回前台、写入完成和后端恢复时自动刷新；手动按钮只作兜底。
- 心流：主界面/夜谈最多显示一张轻量卡片。
- 行动：每卡最多一个可选点击；点击有即时正反馈并记录，不点击无负担。
- 记忆：一级目录、二级目录、可点击叶节点详情必须完整可达。

---

## 暂缓 / 有门槛的后续

- 原生 macOS N1-N5 代码迁移：待发送卡死完成取证、共同逻辑稳定、N0 ADR 通过后启动。
- 完全移除 Python 后端或同时维护 Swift/Python 两套权威业务逻辑。
- Web 新功能、移动端语音、账号、支付、云同步和新小游戏。
