# 当前进度状态

> 人维护的结构化进度视图。
> 最后更新时间：2026-07-02（PM Agent 更新，第 2 轮）

---

## 当前阶段

Mac 应用体验整合与稳定化：M0 基线与盘点。

当前主线已经从 Web demo 完善切换为 Mac 应用。Web/Python 保留为数据和兼容性基线。

### 分支状态

- **automation/quality-loop 领先 main**：分支分歧已由 Executor 解决（`3ee20e7` 合并 main）。当前 quality-loop 领先，串行状态恢复。

---

## 工程基线

### Python / Web

| 指标 | 当前值 | 目标 |
|---|---|---|
| Gate 1 综合通过率 | **100%**（262/262） | >= 95% |
| 失败 | 0 | 0 |
| 关键维度 | accuracy / completeness / functional / api_resilience / framework / robustness 100% | 全部 100% |
| 最近记录的验证 | `python3 -m compileall app`、`python3 -m app.evaluation.runner` | 保持通过 |

### Mac

| 指标 | 当前状态 |
|---|---|
| 首轮三主线实现 | 已提交：`9c08a7a` |
| 编译错误修复 | 已完成：`07db46d`（isDeleted、emotionCurve、saveTodayPlanItems） |
| iOS 构建验证 | ✅ 已通过：`3ee20e7`（移除 app.db 资源引用） |
| 原生 Mac 构建验证 | ❓ 待确认方向 + 执行 |
| 关键路径性能基线 | 待补 |
| 真实数据字段矩阵 | 待补 |
| 双向互融端到端验收 | 待补 |
| Mac 技术方向假设 | 原生 macOS（基于代码中 AppKit 修改推断） |

> Python Gate 通过不构成 Mac 构建、性能或交互验收证据。

---

## 已实现但待验收

- **心流 ↔ 夜谈**：`CompanionGardenView` 已展示部分心流内容，`ChatView` 已加入 `FlowContextBar`。
- **性能首轮修改**：`MemoryListView` / `StateOverviewView` 使用惰性列表；SQLite 增加事务和 SQL 层过滤；`contextMemories` 已优化。
- **UI 内容首轮补齐**：`MemoryCard` 增加 subcategory / updatedAt；Journal 增加情绪曲线、insights、keywords；StateProfile 字段已复核。
- **iOS 构建验证**：Executor 已完成 iOS Release 构建验证，移除了不存在的 app.db 资源引用。

这些条目只表示代码已经存在，不表示目标 Mac 上已经构建、数据完整或性能达标。

---

## 当前 P0

1. 确认原生 Mac 技术方向，完成 macOS target 构建验证，记录平台差异。
2. 在原生 Mac 环境下对启动、页面切换、夜谈发送、长期记忆、心流页和同步建立性能基线。
3. 建立 `SQLite / API → Swift model → Store → View` 字段矩阵。
4. 用代表性脱敏数据检查长期记忆全部类别、核心字段、会后总结和三篇关联日记。
5. 基于性能基线，复现并定位 `CompanionStore.load()`、`syncAllFromBackend`、数据库查询和视图计算中的卡顿。

---

## 已知问题与风险

### 高优先级

- Mac 应用存在卡死和点击反应缓慢，尚无统一复现场景和性能证据。
- 原生 Mac 构建验证尚未完成，技术方向需最终确认。
- 长期记忆类别/字段和三篇关联日记是否完整进入 UI 尚未经过字段矩阵验证。

### 中优先级

- 心流与夜谈已有初步入口，但选择规则、点击详情、来源、更新和空状态尚未完整验收。
- `CompanionStore.load()` 异步化、`syncAllFromBackend` 批量事务和 `StateOverviewView` 计算缓存仍待基线支持后决定。
- Fixer 上一轮因 worktree 路径和分支问题阻塞，需下一轮验证是否恢复。

### 暂缓

- Web 记忆混合检索、session 继续策略、角色统计和 README 截图。
- 移动端语音、账号、支付、云同步和新互动内容。

---

## 下一步

1. 完成原生 Mac 构建验证（M0 首项），明确平台差异。
2. 建立性能基线，用数据而非感觉评估卡顿问题。
3. 完成字段矩阵盘点，确保数据不静默丢失。
4. 按复现证据处理 M1 稳定性问题。
5. 再完成 M2 双向互融的规则、导航和状态闭环。
6. 完成 M3 长期记忆和关联日记的数据展示闭环。
7. 使用脱敏真实数据进行 M4 人工体验验收。
