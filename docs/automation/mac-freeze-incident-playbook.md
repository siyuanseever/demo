# Mac 发送卡死事故处理规范

适用事件：用户点击发送后 Mac App 无响应，且 Python 后端在对应时间窗口没有收到请求。

## 1. 事件定义

- 默认 issue：`MAC-HANG-SEND-001`
- 严重度：`high`
- 分类初值：`needs_instrumentation`
- 当前平台：iOS App 的 Mac Catalyst 迁移版
- 隐私：不得记录消息正文，只记录长度、脱敏 hash、模式和时间。

重复发生时沿用同一 issue ID，新增 occurrence，不创建多个标题不同的重复 issue。

## 2. 最小取证链

每次发送使用一个 correlation ID，并记录以下阶段：

1. `send_tapped`
2. `send_task_started`
3. `request_encode_started`
4. `request_resumed`
5. `backend_received`
6. `first_response_received`
7. `store_apply_started`
8. `store_apply_finished`

同时记录：

- build commit、平台、系统版本、运行模式；
- 会话是否首次发送、群聊/单角色、后端在线状态；
- session/message/memory/journal 数量级，不记录私人内容；
- UI heartbeat 间隔；
- CPU、内存和最后一个成功阶段；
- App 与后端同一时间窗口的脱敏日志。

缺少 `backend_received` 不能自动归因后端；先确认是否达到 `request_resumed`。

## 3. Hang 捕获

满足任一条件即捕获：

- UI heartbeat 间隔超过 1 秒；
- 点击发送后 2 秒内未到达 `request_resumed`；
- App 连续 5 秒无法处理轻量 UI 操作。

捕获内容：

- 主线程 stack sample；
- 其他线程中 SQLite、锁、semaphore、网络和任务等待栈；
- 最近 30 秒阶段事件；
- 后端最近 30 秒 access/application log；
- CPU/内存快照；
- 当前数据规模。

无法自动采样时，Checker 报告具体缺口，状态为 `blocked_by_observability`，不能写“未复现”。

## 4. 复现矩阵

Checker 使用合成消息，至少覆盖：

| 维度 | 场景 |
|---|---|
| 后端 | 在线 / 离线 / 启动后恢复 |
| 发送 | 首次 / 连续 |
| 模式 | 单角色 / 自动群聊 |
| 数据 | 小缓存 / 脱敏真实规模 |
| 同步 | 空闲 / 自动刷新刚完成 |

优先使用 fake model 或确定性本机 stub，避免把模型延迟和 quota 混入 UI 卡死测试。真实模型只做一次人工补充验证。

## 5. 分类规则

- `preflight_main_thread_hang`：未到 `request_resumed`，主线程被 DB、计算、锁或同步 I/O 阻塞。
- `request_dispatch_failure`：编码完成但 URLSession task 未 resume。
- `backend_unreachable_ui_blocked`：后端不可达且 UI 未正常降级。
- `response_apply_hang`：已收到响应，在 Store/View 更新阶段卡死。
- `resource_exhaustion`：CPU、内存或任务数量异常。
- `insufficient_evidence`：缺少关键阶段或 stack，不允许猜测根因。

### 当前候选点（不是结论）

代码审查显示 `CompanionStore` 整体标记为 `@MainActor`，发送入口会先追加消息并修改多个 published state，再进入网络 await。Checker 应优先确认：

- `messages.append` / `isSending` 是否触发昂贵或递归的 SwiftUI 重算；
- 请求前是否发生同步 SQLite、全量派生数据或主线程锁等待；
- `currentSessionID`、request encoding 和 `URLSession.bytes` 分别是否到达；
- stream callback 应用状态时是否出现主线程长任务；
- 后端地址错误是否能快速降级，而不是造成 UI 等待。

以上只决定观测点，不允许 Fixer 在没有 stack/阶段证据时直接按猜测修改。

## 6. 四 Agent 处理顺序

### PM

只下发一个任务。顺序固定：

1. 缺观测能力：下发最小 instrumentation 任务；
2. 有观测无复现：下发复现环境/测试基础设施任务；
3. Checker 已复现：不再派 Roadmap 功能，等待 Fixer；
4. Checker 验证修复后，再恢复其他产品任务。

### Executor

只实现 PM 明确授权的观测或测试基础设施，不直接宣称修复卡死。允许增加脱敏阶段事件、heartbeat、correlation ID 和空的 UI-test target/project wiring；不得编写测试断言。

### Checker

编写和运行复现测试，采集证据并分类。专用测试目录和测试断言归 Checker。若 UI-test target 不存在，先报告基础设施缺口，不能修改产品行为绕过。

### Fixer

仅在 Checker 已稳定复现并给出最小失败测试/证据后修产品。修复范围必须能解释最后成功阶段和 stack。

## 7. 回归门槛

修复不能只以“这次没卡”关闭。至少满足：

- 同一复现场景连续发送 10 次无 hang；
- 后端在线时每次都能关联到 `backend_received`；
- 后端离线时 UI 保持响应并进入明确降级；
- 关键场景运行 20 分钟无 UI heartbeat 超限；
- Catalyst 构建通过；
- Checker 独立复验，Fixer 不得自行关闭 issue。

真实数据规模或真实模型无法自动验证时，保留 `pending_manual_validation`，但确定性回归必须先通过。

## 8. 原生迁移关系

此 incident 必须先在 Catalyst 基线上完成取证。N0 可以并行做架构盘点，但 N1 以后不能作为规避 incident 的替代方案。原生夜谈纵切必须复用同一阶段事件和回归门槛，证明没有把卡死根因一起迁移。
