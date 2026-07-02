# Mac 内存失控事故处理规范

适用事件：Mac App 内存持续单调增长，已观察到约 65GB，占用不回落并伴随卡死风险。

## 1. 事件定义与安全边界

- issue：`MAC-MEM-GROWTH-001`
- 严重度：`critical`
- 当前状态：`needs_reproduction_and_memgraph`
- 优先级高于普通 Roadmap 功能和 `MAC-HANG-SEND-001`；两者证据需要关联。

安全规则：

- 自动测试进程 resident memory 达到 2GB 时立即停止该次场景并保存证据。
- 用户日常运行发现持续增长时退出 App，不等待其达到系统内存压力。
- 不在报告中持久化对话正文、数据库原文或 API key。

## 2. 已发现的确定问题与候选风险

### `MEM-001`：Mach 内存释放参数错误

`SendInstrumentation.cpuUsage()` 调用 `task_threads` 后，`vm_deallocate` 使用了指针 `hashValue`，并且释放 size 未按 thread 数量乘以 `MemoryLayout<thread_t>.stride`。这不能正确释放 `task_threads` 返回的 Mach allocation。

该问题必须由 Checker 建立回归、Fixer 修复。尚不能断言它独立造成全部 65GB。

### `MEM-002`：heartbeat 无背压

200ms heartbeat timer 每次都向 main queue 投递闭包。主线程长时间卡住时，没有“已有 tick 待执行”的 in-flight 限制，待执行闭包可能持续积压。

### 其他必须排查

- `activeSends` 在取消、异常或永久等待时是否最终清理；
- 两个永久 timer 是否被重复创建或意外产生多个 singleton 实例；
- SwiftUI `messages`、派生数组、图片和详情视图是否被历史闭包/Task 持有；
- SSE `dataLines` 在缺少事件分隔符时是否无界增长；
- 自动同步、数据库结果和 View 计算是否反复复制全量数据；
- URLSession stream、Task 和 callback 是否形成 retain cycle。

## 3. 最小测量协议

每次样本必须记录：

- commit、构建配置、macOS 版本、数据规模；
- 场景开始/结束时间；
- resident memory、physical footprint、virtual size；
- timer 数、线程数、Task/发送数、`activeSends` 和 heartbeat pending 数；
- Allocations/Leaks trace 或 memgraph 路径；
- app-owned leaked type、数量，以及至少一条 ownership path；无 root path 时使用 grouped leak tree；
- 场景结束后 5 分钟的回落情况。

不得只使用 Activity Monitor 单个瞬时数字宣称修复，也不得因为修复后 memgraph 文件更小就宣称泄漏消失。必须证明同一场景下具体 retained type/ownership path 消失或不再增长。

## 4. 复现矩阵

Checker 依次运行，找到最小增长场景：

1. 启动后空闲 20 分钟；
2. 打开夜谈但不发送；
3. 使用 fake/stub 后端连续发送 10 次；
4. 后端无响应时等待 2 分钟；
5. 人为阻塞主线程 10 秒，验证 heartbeat 队列是否有界；
6. 反复进入/离开心流、记忆、日记页面；
7. 自动同步 10 次；
8. 使用脱敏真实规模数据库重复关键场景。

对 `30c0d36` 前后做 A/B：同一环境、同一数据、同一场景。若仅新 commit 增长，优先审查 instrumentation；若两边都增长，继续隔离共同代码。

## 5. 自动失败门槛

- resident memory 达到 2GB：立即终止场景，状态 `critical_memory_limit`；
- warm-up 后空闲增长持续超过 5MB/分钟达 10 分钟：失败；
- 同一操作重复 10 次后，GC/回落等待 5 分钟，physical footprint 比 warm-up 高 20% 以上：失败；
- heartbeat pending 数、active send 数、timer 实例数随时间单调增长：失败；
- Allocations 中同一类型持续净增长且无业务对象数量对应关系：失败。

阈值用于发现失控，不是最终产品预算。最终内存预算应基于脱敏真实数据基线另行确定。

## 6. 四 Agent 工作流

### PM

只在 handoff 中下发一个 incident task。顺序：

1. Checker 可直接复现：等待 Checker issue，交给 Fixer；
2. 缺测试入口：下发最小 `test_infrastructure`；
3. 缺产品观测字段：下发最小 `memory_observability`；
4. incident 未关闭前，不下发原生迁移或普通 UI 功能。

PM 不修改或提交任何仓库文件。

### Executor

只能实现 PM 明确授权的观测/空测试 target。不得根据 65GB 数字直接大范围重构，也不得把增加日志写成修复完成。

### Checker

- 先为 `MEM-001`、`MEM-002` 写最小回归；
- 执行 A/B、复现矩阵和内存上限保护；
- 生成稳定 issue，附 allocations/memgraph 摘要；
- 对每个 app-owned leaked type 标明预期生命周期（process/session/view/request/task）和首个 app-owned retaining edge；
- 对无证据的候选点保持 `needs_instrumentation`。

### Fixer

- 先修确定的内存管理错误，再逐个处理 Checker 的稳定失败；
- 一个根因一个 commit；
- 不修改测试，不放宽阈值；
- 只有 Checker 可以关闭 incident。

## 7. 必需回归

至少包含：

- 重复 CPU/thread 采样后 Mach allocation 不持续增长；
- 主线程阻塞时 heartbeat pending work 有严格上限；
- 发送成功、失败、取消后 `activeSends` 最终归零；
- 10 次 fake 发送后内存回到允许区间；
- 20 分钟 idle/soak 无持续斜率；
- 同一场景 before/after 中，目标 leaked type 或 retaining path 消失；剩余 framework/runtime noise 单独列出；
- 后端离线和 SSE 中断不产生无界 buffer；
- Catalyst 构建通过，Checker 独立复验。

## 8. 与原生迁移的关系

原生 macOS 迁移不能作为内存事故的替代修复。N2 夜谈纵切和 N3 数据纵切必须复用相同内存门槛；只有 Catalyst 与原生版本都通过共享服务层回归，才能证明没有迁移泄漏根因。
