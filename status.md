# 当前进度状态

> 人维护的结构化进度视图。
> 最后更新时间：2026-07-02（PM Agent 更新）

---

## 当前阶段

`ROADMAP.md` Phase 3：做出可演示 demo + Harness 基础设施建设

---

## 总体进度

- **已完成任务**：25 项（见 `TODO.md` ## 已完成）
- **进行中任务**：1 项
- **近期待办**：5 项
- **iOS 方向**：待启动
- **Agent 方向（Maker/Checker）**：架构设计阶段

### 工程基线

| 指标 | 当前值 | 目标 |
|------|--------|------|
| Gate 1 综合通过率 | **100%** (262/262) | >= 95% |
| 总检查数 | 262 | - |
| 通过 | 262 | - |
| 失败 | 0 | 0 |
| 关键维度 | accuracy / completeness / functional / api_resilience / framework / robustness 100% | 全部 100% |
| 最近验证命令 | `python3 -m compileall app`、`python3 -m app.evaluation.runner` | - |

> CHK-006（sync_token 空字符串认证绕过）已修复：本地地址白名单（127.0.0.1/localhost/::1）无需 token，远程调用必须提供非空 sync_token。

---

## 进行中项

### Mac 应用三大需求开发

- **心流 ↔ 夜谈互融**：CompanionGardenView 已展示心流目标/温柔提醒/摆烂日记；ChatView 已新增 FlowContextBar
- **性能优化**：MemoryListView / StateOverviewView 已改为 LazyVStack；SQLiteDatabase 已加事务封装和 SQL 层过滤；contextMemories 已优化
- **UI 内容完整性**：MemoryCard 已补全 subcategory / updatedAt；Journal 已补全情绪曲线/insights/keywords；StateProfile 字段已确认完整
- **阻塞/待决策**：
  - CompanionStore.load() 异步化需 Xcode 真机验证，暂不实施
  - syncAllFromBackend 批量写入事务优化需 Xcode 验证，暂不实施
  - StateOverviewView 计算属性缓存改动影响面广，作为后续优化

---

## 最近完成（最近 3-5 项）

1. ✅ Mac 应用三大需求第一阶段：心流 ↔ 夜谈互融 + 性能优化 + UI 内容完整性
2. ✅ 修复 CHK-006：sync_token 本地白名单 + 非空校验，Gate 1 恢复 100%（262/262）
3. ✅ 修复 CHK-005/007：请求体 1MB 限制 + POST 参数缺失返回 400
4. ✅ 自动化 Agent 体系：PM Agent + Executor Agent + Checker + Fixer 四角色 + Schedule 调度
5. ✅ 长期状态画像：跨会话追踪用户心理状态，支持版本历史

---

## 已知问题 / 技术债务

### 高优先级

- **记忆检索仍为单一策略**：未实现混合检索，可能导致无关记忆污染 prompt 或关键记忆遗漏
- **已结束 session 继续对话状态不清晰**：用户可能困惑当前是"追加"还是"新 session"

### 中优先级

- **群聊自动 UI 表达生硬**：当前仅靠关键词规则，缺少角色切换的过渡提示
- **数据看板缺少角色维度**：无法分析"哪个角色在什么情绪下被触发"
- **README 截图过时**：展示的不是当前六角色 UI

### 低优先级 / 长期

- **iOS 方向尚未启动**：Xcode、SwiftUI、STT/TTS 均未开始
- **意图识别系统重构待排期**：`intent-routing-integration.md` 有计划但未实施
- **Agent 方向（Maker/Checker）仅完成架构设计**：尚未拆分实现

---

## 下一步建议

1. **Xcode 编译验证**：在 Xcode 中编译 iOS 项目，确认 Swift 语法无错误
2. **Mac Catalyst 真机测试**：验证 CompanionGardenView 心流展示、ChatView FlowContextBar、MemoryListView 字段补全
3. **CompanionStore.load() 异步化**：验证后台线程数据库查询不会导致界面冻结
4. **确定记忆混合策略的参数**：先设定一个合理初值（如相关 5 条 + 近期 3 条 + 重要 2 条），在真实对话中验证后调优
5. **选择 session 继续方案**：在方案 A（允许追加）和方案 B（分支新 session）中做决策

---

## 最近验证记录

| 时间 | 验证项 | 结果 |
|------|--------|------|
| 2026-07-01 | compileall | 通过 |
| 2026-07-01 | check_sse_stream | 通过（渲染 JS + deep/quick SSE 契约） |
| 2026-07-01 | evaluation.runner | **100% 通过（236/236），Gate 1 通过** |
| 2026-07-01 | manual_eval | 5 个用例待人工评分，不计为 Gate 4 通过 |
| 2026-07-02 00:00 | compileall | 通过 |
| 2026-07-02 00:00 | check_harness | 通过 |
| 2026-07-02 00:00 | evaluation.runner | **99.62% 通过（263/264），Gate 1 未通过（robustness CHK-006）** |
| 2026-07-02 00:00 | diagnose | 1 项 needs_confirmation |
