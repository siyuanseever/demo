# Maker / Checker 架构方向（未实现）

本文只记录未来可能采用的架构方向。仓库当前没有双 Agent 运行时、`app/loop/`、Ralph runner、自动任务选择、loop state 或 loop memory。

## 当前实际流程

当前由 Codex 在一个明确任务内完成：

1. 读取 `AGENTS.md`、`plan.md`、`status.md` 和待改代码；
2. 实现小范围变更；
3. 按变更类型运行 Harness；
4. 失败时运行 `diagnose` 并确认产品契约；
5. 汇报变更、验证结果和未决风险。

这是一套修改—检查纪律，不代表 Maker 和 Checker 已经物理隔离。

## 未来目标

如果后续确实需要并行或自动化，可以再设计两个独立角色：

| 角色 | 职责 |
|---|---|
| Maker | 在独立 branch/worktree 实现一个明确任务 |
| Checker | 只验证 diff、运行门控、输出 verdict，不扩大需求 |

Checker verdict 建议包含：

```json
{
  "verdict": "pass | product_defect | test_defect | needs_review",
  "source_commit": "commit SHA",
  "gate_results": {
    "syntax": true,
    "functional": true,
    "web_sse": null,
    "prompt_review": null,
    "experience_review": null
  },
  "failed_checks": [],
  "risk_level": "low | medium | high",
  "notes": ""
}
```

## 引入条件

只有满足以下条件才值得实现双 Agent：

- 单 Agent 修改与自检反复出现系统性漏检；
- 并行任务数量足以抵消 worktree 和合并成本；
- verdict schema、任务来源、失败恢复和人工介入点已经明确；
- 有可重复的基准证明收益，而不是只增加流程复杂度。

## 必要的人类介入

- 安全策略或危机场景行为变化；
- 测试契约存在多种合理解释；
- Checker 无法区分产品缺陷和测试缺陷；
- 涉及真实心理对话数据、隐私或外部写操作；
- 连续失败或自动修复开始扩大需求。

## 当前决定

- 不实现 Loop 或双 Agent 运行时。
- 不创建虚假的 state、memory、runner 或 Web API。
- 保留 Harness 作为独立、可执行、以退出码判定的工程基础设施。
- 将来若重启该方向，从新的需求和基准重新设计，不沿用不存在的 Hook。
