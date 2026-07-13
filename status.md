# 当前进度状态

> 人维护的结构化进度视图。
> 最后更新时间：2026-07-13（原生 macOS N2 DeepSeek 直连夜谈纵切完成）

---

## 当前阶段

原生 macOS N3 数据纵切完成，进入 N4 Catalyst/Native 并行验收。Catalyst 继续作为兼容和性能对照，不再是唯一的 Mac 产品实现。

原生 App 直接调用 DeepSeek，并将消息、日记、记忆和长期状态写入自己的沙盒 SQLite；正常使用不依赖 Python 或 SSE。Web/Python 继续维护既有 Web UI 与仓库数据，两个运行时暂不自动互相覆盖。

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
| Mac 本地直连回复顺序 | `implemented_verified`：契约测试连续 10 轮验证 quick 与 plan 并行，quick 先显示，plan 决定 deep、quick_only、clarify 或 interaction |
| Mac 对话轨迹 | `implemented_verified`：夜谈右侧显示轻量轨迹；悬停或点击展开问答预览，点击条目可定位原始用户消息 |
| Mac 语音输出 | `implemented_pending_listening_validation`：免费本地 Qwen3-TTS 0.6B 8-bit + Serena；支持常驻服务、单条播放/停止、生成状态、试听、自动朗读、失败提示和缓存；25 字实测约 4 秒 |
| 每周心流导航 | `implemented_pending_runtime_verification`：App 启动/回前台按自然周检查；本地 Key 模式直接调用 DeepSeek 生成并写入 SQLite，不再依赖手动按钮 |
| 夜谈用户状态卡 | `implemented_pending_runtime_verification`：右栏心理地图已替换为本轮结构化状态、核心需要、风险、回应模式和规划理由 |
| 回复价值评估集 | `awaiting_user_scores`：已选 24 条候选，八类主题各 3 条，来自 14 个 session；本地评分页面已生成 |
| 单条消息发送后卡死、后端无请求 | P0，仍需按独立复现场景验证 |
| 内存持续增长至约 65GB | `fixed_pending_verification`：已修 MEM-001/MEM-002 和 SSE 1MB 上限，等待发送/同步/20 分钟 soak 独立复验 |
| 自动刷新 | 当前 `syncIfNeeded()` 不执行同步，仍依赖手动刷新 |
| 数据权威边界 | 已在规划中确认，尚未实现验收 |
| 字段矩阵 | `implemented_verified`：见 `docs/n2-data-field-matrix.md`，原生 SQLite 往返测试覆盖 journal、memory、state profile 关键字段 |
| 记忆二级目录/叶节点详情 | `implemented_verified`：Catalyst 分类视图与详情已实机检查；原生资料库提供分类、摘要与详情入口 |
| 最近更新日记/记忆入口 | `implemented_verified`：Catalyst 最近更新模式与周分组日记已实机检查；原生资料库按更新时间排序 |
| 心流单卡片轻互动 | 部分 UI 存在，完整交互未验收 |
| 原生 macOS 迁移 | `N3 implemented_verified`：在 N2 直连夜谈基础上，完成本地会话关联、记忆分类/最近更新、日记周分组/心情曲线、长期状态、每周心流缓存和 Yoyo 表情头像；下一阶段为 N4 |

---

## 当前 P0

1. `RESPONSE-VALUE-001`：建立 20–30 条本地私密真实案例集，完成当前回复价值基线评分。
2. 将 Plan 升级为 Response Strategy Agent，明确本轮价值目标、候选洞察、记忆证据和 avoid 项。
3. 对 Mac 双阶段发送执行连续 10 轮真实发送，确认 quick 先显示、plan 后决策、按需追加 follow-up，且界面响应和 correlation ID 完整。
4. Checker 对 `30c0d36` 前后执行内存 A/B，并复验 `MAC-MEM-GROWTH-001` 修复。
5. 完成真实发送、离线后端、页面切换、同步和 20 分钟 soak；2GB 自动止损。
6. 让实际定时任务加载 v3 Prompt，并用一次 dry run 证明协议、分支、cwd 和单任务约束。
7. 停止 PM/Executor 小时级轮询，按 P0 调度表错峰运行。
8. 验证 PM 没有任何 Git 写操作，以及三个代码 Agent 的固定 worktree 保护。
9. Checker 在同一 automation HEAD 上复核 Catalyst 构建、Python Gate 和 Executor 证据。
10. 建立卡死复现场景和六条关键路径性能基线。
11. 为发送路径建立脱敏阶段事件、correlation ID、UI heartbeat 和 hang 采样方案。
12. 完成自动刷新触发矩阵与数据字段矩阵。
13. 按一级类别 → 二级类别 → 叶节点详情核对长期记忆导航。
14. 核对最近更新记忆/日记和三篇关联日记的可见性。

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

### 2026-07-13 原生 N2 验证证据

- `SensenStoryNative`、Mac Catalyst 和 generic iOS 三个目标均无签名 Debug 构建通过。
- 原生二进制未包含 `/api/chat/stream`、`text/event-stream` 或 SSE 错误文案；`ChatService` 实现仅编入 Web/Catalyst 兼容平台。
- 本地 DeepSeek 契约测试通过：quick 与 plan 并行、quick-only 分支、按需 deep、连续 10 轮顺序和 SQLite 持久化均符合预期。
- 原生 20 秒空闲 RSS：峰值 `127.1 MB`，前后窗口增长 `8.3 MB`。
- Catalyst 30 秒空闲 RSS：峰值 `158.5 MB`，前后窗口增长 `10.4 MB`。
- 上述短时回归没有出现失控增长，但不能替代真实发送和 20 分钟 soak，因此 `MAC-MEM-GROWTH-001` 暂不关闭。

---

## 已确认的产品方向

- 当前实现：Catalyst 兼容基线 + 原生 macOS N2；原生 target 是新主线。
- 原生数据：沙盒 SQLite 是运行数据源，DeepSeek 由 App 直接调用，不经过 Python/SSE。
- Web 数据：Python 后端和仓库 `data/app.db` 继续服务 Web UI；跨运行时同步另行设计。
- 心流：主界面/夜谈最多显示一张轻量卡片。
- 行动：每卡最多一个可选点击；点击有即时正反馈并记录，不点击无负担。
- 记忆：一级目录、二级目录、可点击叶节点详情必须完整可达。

---

## 暂缓 / 有门槛的后续

- 原生 macOS N4-N5 并行验收和默认产品切换。
- 原生与 Web 数据库之间的自动同步；在冲突策略明确前不建立隐式双向写入。
- Web 新功能、移动端语音、账号、支付、云同步和新小游戏。
