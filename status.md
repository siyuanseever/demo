# 当前进度状态

> 人维护的结构化进度视图。
> 最后更新时间：2026-07-14（原生 macOS N3 界面与交互收敛）

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
| Mac 对话轨迹 | `implemented_verified`：夜谈左侧叠加轻量轨迹，与右侧系统滚动条分离；连续悬停区域展开问答预览，点击条目可定位原始用户消息 |
| Mac 语音输出 | `implemented_pending_listening_validation`：免费本地 Qwen3-TTS 0.6B 8-bit + Serena；支持常驻服务、单条播放/停止、生成状态、试听、自动朗读、失败提示和缓存；25 字实测约 4 秒 |
| 每周心流导航 | `implemented_pending_runtime_verification`：App 启动/回前台按自然周检查；夜谈停留期间卡片不自动轮播，仅在重新进入夜谈或用户手动点击时切换 |
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
| 原生 macOS 迁移 | `N3 implemented_verified`：在 N2 直连夜谈基础上，完成独立 ICNS 忧忧兔图标、全量历史会话与记忆加载、跨资料搜索、资料来源夜谈导航、中文记忆分类/最近更新、日记周分组/心情曲线、六维长期状态及版本历史、每周心流缓存和随回复变化的 Yoyo 表情头像；下一阶段为 N4 |

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

### 2026-07-14 原生图标与首条消息回归

- 首条消息界面始终保留同一 `ScrollView`，空状态改为覆盖层，避免消息数组从空变为非空时触发 SwiftUI `AttributeGraph` 循环。
- 原生图标改为独立 `SensenStoryNative.icns`；应用包不再包含 `Assets.car`，图标资源从约 `1.6 MB + 94 KB` 收敛为 `94 KB`。
- ICNS 版本 30 秒空闲 RSS 约 `121216–121248 KB`，仅波动 `32 KB`；无图标对照约 `125728–125808 KB`，证明 ICNS 不是当前绝对内存占用来源。
- `SensenStoryNative` clean build 与 `scripts/test_native_n2.sh` 均通过；真实发送和 20 分钟 soak 仍待继续验证。
- 真实界面核对右栏头像绑定最新 assistant `expressionID`，与 iOS 共用忧忧兔七种表情资源；新增 `NSCache`，避免 SwiftUI 重算时重复解码头像。
- 本地资料 335 条记忆已将全部历史英文/中文别名归并为 8 个中文大类，实机计数守恒，不再出现孤立 legacy 分类。
- 心流卡片停留夜谈 2.5 秒保持不变；切到资料页再返回后切换到下一张，符合“聊天时不打扰、页面切换时轮换”。
- 历史会话搜索、展开、继续夜谈实机可用；左侧对话轨迹与右侧滚动条和状态栏保持分离。

### 2026-07-14 原生资料导航与 20 分钟稳定性回归

- 原生 App 连续 20 分钟采样 41 次：RSS `173088 KB → 173200 KB`，净增仅 `112 KB`；最高 `184784 KB`，早期页面切换峰值随后回落，后半程平均值低于前半程。
- 进程采样显示主线程停留在正常 AppKit 事件循环，physical footprint `81.6 MB`、peak `128.4 MB`，未发现死锁或持续 CPU 占用。
- 历史会话改为按时间段折叠，默认只展开最新分组；搜索时自动展开匹配分组，清空搜索后恢复默认折叠状态，避免一次构造全部会话的超大无障碍树。
- 实机验证搜索“雨雨怪”后仅展开匹配的 `6月` 分组；清空后 `今天` 保持展开，`昨天/本周/7月/6月/5月` 均恢复折叠。
- `git diff --check`、`scripts/test_native_n2.sh` 和 `SensenStoryNative` clean build 均通过；契约测试覆盖 quick/plan 并行、quick-only、按需 deep、连续 10 轮和 SQLite 持久化。

### 2026-07-15 原生真实 DeepSeek 发送回归

- 新增 `scripts/test_native_deepseek_smoke.sh`，从本地环境读取 Key，使用一次性临时 SQLite，不读取或写入用户历史资料，也不输出回复正文。
- 真实简单输入验证 `quick + plan → quick_only`：quick `0.97s`，完整路由 `5.37s`，持久化 2 条消息。
- 真实复杂输入验证 `quick + plan → deep`：quick `0.87s`，完整链路 `8.71s`，持久化 user/quick/deep 共 3 条消息。
- 两轮均成功解析结构化回复，没有把 `reply`、`expression_id` 等 JSON 外壳泄漏到展示文本；quick 回调均早于 Plan/Deep 完成。
- 原生 SwiftUI 使用隔离数据库完成真实首条发送：quick 到达时界面保持可点击，deep 到达后 user/quick/deep 三条消息同时保留，没有 `AttributeGraph` 循环或覆盖首条回复。
- 实机暴露并修复 deep 原样重复 quick 开头的问题：服务层会在持久化前移除完全相同且边界明确的 quick 前缀；如果 deep 只剩重复内容，则不再追加无信息量消息。
- 修复后再次实机验证，quick 与 deep 从不同内容起点继续；切到“本地资料”再返回“夜谈”，三条消息和右侧评估状态均完整保留。
- 发送后 30 秒 RSS 共 16 个样本：首次惰性加载从 `148288 KB` 一次升至约 `162432 KB`，随后 13 个样本保持稳定，没有持续增长。

### 2026-07-15 原生本地资料展示闭环

- 本地资料概览从单纯计数扩展为“最近更新 + 记忆地图”：同时显示最近夜谈、日记情绪与心情分数、最近记忆分类、最新状态画像，以及八类记忆的实时数量。
- 八类记忆卡片均可点击；实机验证点击“支持资源”后直接进入记忆页、滚动并展开该类别，显示 `43` 条记录及其小类，不再只是打开全部列表。
- 历史会话展开后统一展示关联日记、情绪变化、洞察、下一步、关键词、记忆大类/小类/重要度/依据，以及长期状态强度、趋势和支持方式。
- 使用真实本地数据验证概览数字、最近更新摘要、八类记忆计数和已总结会话的 3 条关联记忆均能完整显示；来源夜谈与继续对话入口保持可用。
- `SensenStoryNative` 构建通过，概览、记忆分类直达、历史会话展开等交互均已在运行中的原生 App 验证。
- 日记页按 `session_id` 选择每段夜谈的最新总结来计算心情曲线和周报，避免重复点击总结产生的多个版本扭曲趋势；旧版本仍保留在“同一会话的历史总结”中。
- 实机验证本周从原先错误的“9 篇日记”修正为“3 段夜谈的最新日记 + 6 个历史版本”，平均心情和主要情绪随之按独立夜谈重新计算。
- 长期状态历史行补充阶段、强度、置信度、支持方式和最多两条依据；当前卡不再重复显示两次“当前状态”。实机展开 15 条历史记录验证字段可见。
- N4 快速页面切换回归中，连续访问夜谈、心流、资料、诊断和设置时 Computer Use 辅助管道因高频无障碍树抓取断开；App 进程仍持续存活，CPU `0.0%`，主线程停留在正常 `mach_msg` AppKit 事件循环。
- 切页后进程采样 physical footprint `103.5 MB`、peak `120.4 MB`，未发现 AttributeGraph 循环、主线程阻塞或内存失控；这次故障归类为测试控制管道过载，而非 App 卡死。
- 最新构建再次通过 `scripts/test_native_n2_memory.sh`：20 秒 RSS peak `131.2 MB`，early `117.3 MB`，late `128.4 MB`，增长 `11.2 MB`，低于门控阈值；测试后已恢复普通数据路径启动。
- 源码复核确认对话轨迹仅左侧 44pt 连续命中区接收交互，预览卡不接收点击；本周心流没有定时轮播，只在从其他页面返回夜谈时推进一张，也可由用户手动切换。
- 自动语音触发改为只监听新 assistant 消息 ID；页面切换后返回夜谈不会重复播放上一条回复。TTS 服务仍以单生成锁串行执行推理，避免 quick 播放与 deep 预取同时占用两份模型内存。
- 原生 target 已补齐默默兔 8 张、悠然兔 5 张表情资源；构建包现含忧忧兔 7 张、默默兔 8 张、悠然兔 5 张，共 20 张，与三形态定义一致，不再因资源缺失退回系统占位图。
- 资源补齐后 `SensenStoryNative` 构建、`scripts/test_native_n2.sh` 与 `scripts/test_native_n2_memory.sh` 再次通过；内存门控 peak `131.2 MB`、增长 `11.2 MB`，首条 quick/deep 消息链路未复现 `AttributeGraph` 循环。
- quick 回复的结构化协议新增 `character_id`：快速模型会独立选择忧忧兔、默默兔或悠然兔及其合法表情，不再永远沿用上一形态；quick 与 plan 仍并行，不增加首条回应等待。
- 新增三形态契约回归：默默兔 `quick_only` 会把 `momo/encouraging` 同时写入回调和 SQLite；悠然兔 `deep` 会让 quick/deep 都保存 `yoran/serene`，右侧动态头像可直接跟随最新 assistant 元数据。
- 真实 DeepSeek 冒烟再次通过：quick `1.32s`、完整 deep 链路 `12.51s`、持久化 3 条消息；回复 JSON 外壳未泄漏，真实形态和表情均经过合法性校验。
- 上述协议调整后原生构建和内存门控再次通过：RSS peak `131.2 MB`、early `117.2 MB`、late `128.4 MB`、增长 `11.1 MB`。
- 夜谈右侧“本周心流”新增可见的完整导航入口；空状态也可直接前往心流页，不再只能阅读或用左右箭头切卡。
- 原生实机点击右侧入口后成功进入“本周心流导航”，再点击侧栏返回夜谈后卡片从“主要方向”推进到“次要方向”；停留聊天页 2.5 秒仍保持不变，验证“页面切换时轮换、聊天时不自动打扰”。
- 首版把入口放在卡片底部时被固定高度裁切；实机截图发现后已改为标题栏 `arrow.up.right.square` 按钮，并通过无障碍树确认按钮可点击，避免把仅构建成功误判为交互完成。
- quick 与 plan 并行时新增“单轮形态协调”：只要 quick 已经显示，后续 clarify/interaction/deep 都沿用该形态；quick 失败时才由 plan 的形态接管，避免同一轮回复中途换兔子。
- 契约测试故意制造 quick=`momo/encouraging`、plan=`yoyo/understanding` 的冲突，最终 quick/deep 均保存为默默兔；同时修复了 `CompanionCharacter.expression(id:)` 会默认回退、不能用于严格校验的误用，无效 deep 表情现在沿用本轮有效表情。
- 真实 DeepSeek 再次通过：quick `1.34s`、总计 `10.46s`，本轮 quick/deep 均为 `yoyo`，表情分别为 `gentlesmile/understanding`；测试不输出回复正文。
- 协调逻辑后的原生构建与内存门控通过：RSS peak `121.9 MB`，early `121.9 MB`，late `121.8 MB`，growth `-0.0 MB`。
- 新增 `docs/native-macos-n4-acceptance.md`，逐项记录构建、发送、三形态、轨迹、心流、资料、总结、TTS、内存和 Catalyst 对照的完成条件、证据及缺口。
- 原生 close-session 契约新增完整抽取与重复总结回归：第一次写入 journal、2 条记忆、6 域审阅和 1 项状态更新；继续同一 session 后再次总结会新增 journal 版本、记忆和状态历史，不会返回旧总结。
- 隔离数据库真实 UI 完成“发送 → 结束并总结”：总结卡默认展开，展示摘要、心情、关键词、洞察、下一步和真正变化的长期状态；结束后总结按钮禁用，不会再次触发无 active session 错误。
- 心流导航刷新已从总结主等待链路移到后台；实机总结完成后立即移除“正在整理”状态，7 秒后界面仍可操作且完成提示保持，正式本地数据库随后已恢复启动。
- 原生 Debug 构建支持通过 `SENSEN_DEEPSEEK_ENDPOINT` 临时指向本机 fixture；Release 与未设置变量的 Debug 构建仍固定使用 DeepSeek 官方端点，便于做可重复 UI 回归而不改变正式行为。
- 三形态 UI 实机验收完成：默默兔 `quick_only` 后，标题、消息头像和右栏头像均显示“默默兔 · 鼓励你”；悠然兔 `quick + deep` 后，两条 assistant 消息与右栏均保持“悠然兔 · 平静”，未出现同轮换兔或消息覆盖。
- 三形态 fixture 进程与隔离数据库 App 已关闭；随后重新启动普通原生 App，确认本周心流“照顾停药反应后的身体恢复”可见，正式本地数据库路径已恢复。
- 三形态 UI 验收后的最终门控通过：`test_native_n2.sh`、原生 `xcodebuild` 和内存门控均为成功；最新 RSS peak `131.7 MB`、early `117.7 MB`、late `128.9 MB`、growth `11.2 MB`，日常 App 已再次恢复启动。
- 新增 `scripts/test_tts_service.sh`：验证本机 4-bit TTS 健康状态、短句流式 WAV、108 字四分段长文本、音频格式/时长和缓存命中；实测 short `5.6s`、long `22.4s`、cache `0.004s`，四段均一次生成成功且没有漏段。
- 新增 `scripts/test_native_speech_offline.sh` 与 `NativeSpeechOfflineSmoke.swift`：Debug 可通过 `SENSEN_TTS_BASE_URL` 注入端点，离线失败会清空 preparing/speaking/active 状态并保留文字路径，立即停止也不会残留播放状态。
- 原生与 Catalyst 的语音按钮现在跟随消息形态显示“听忧忧兔说 / 听默默兔说 / 听悠然兔说”，辅助功能说明也使用对应角色名，不再固定写忧忧兔。
- 同版本 Catalyst/Native 构建均通过；20 秒空闲对照中 Native RSS peak `131.6 MB`、growth `11.2 MB`，Catalyst peak `151.5 MB`、growth `8.1 MB`。完整 UI 同数据对照仍待人工窗口验收。
- TTS 新增 `/v1/audio/speech/cancel`：停止按钮不仅取消本地播放和 URLSession，也会中止服务端正在执行或等待锁的非流式预取，避免 deep 预取继续占用模型并阻塞下一条语音。
- 新增 `scripts/test_tts_cancel.sh` 真实生成中取消门控：未缓存长文本在 1 秒后被取消，客户端以预期的 chunked incomplete `curl_status=18` 结束，服务健康检查正常，随后短句/长文本/缓存门控再次通过。
- Python Gate 0、Gate 1 全部通过（325/325）；Native 与 Catalyst 均重新构建成功。
- 修复 Catalyst 设置页数据库文件选择器 delegate 立即释放的问题，并改用现代 `UTType.data` API；构建日志不再出现 weak delegate 和废弃初始化警告。
- Native 与 Catalyst 的自动朗读触发从“观察当前消息列表最后一条”改为独立的 live-assistant 事件：只有本轮实时生成的 quick/deep 会进入语音队列，打开历史会话、加载本地缓存和页面返回不再误读旧回复。
- live-assistant 改动后原生 N2/N3 契约与 Native/Catalyst 构建再次通过；UI 鼠标试听仍因当前 Mac 锁屏待补。
- 最新 Native 内存门控通过：20 秒 RSS peak `121.9 MB`、early `121.9 MB`、late `121.8 MB`、growth `-0.1 MB`，实时语音事件和远端取消没有引入持续增长。

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
