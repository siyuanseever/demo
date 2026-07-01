# Issue 报告约定

本目录保存某次评估产生的问题快照，供 Codex 或人工审查。报告不是事实来源；是否仍然存在必须由当前代码和当前门控复现确认。

## 读取规则

1. 先运行 `python3 -m app.evaluation.runner`。
2. 只处理当前报告仍能复现的问题。
3. `product_bug` 可以在产品契约明确、修复风险低时直接修复。
4. `test_bug` 和 `needs_confirmation` 必须先确认测试契约。
5. `observation` 不计入通过率，也不能描述为产品缺陷。
6. 修复后由同一套门控回归，不依赖特定 Agent 或外部工具确认。

## 文件命名

`issues_YYYYMMDD_HHMMSS.json`

## 推荐结构

```json
{
  "schema_version": 2,
  "report_id": "issues_20260701_203000",
  "generated_at": "2026-07-01 20:30:00+08:00",
  "source_commit": "git commit SHA",
  "command": "python3 -m app.evaluation.runner",
  "baseline": {
    "total_checks": 236,
    "passed": 236,
    "failed": 0,
    "pass_rate": 1.0,
    "gate_passed": true,
    "eval_report_path": "eval_reports/eval_report_....json"
  },
  "issues": [
    {
      "id": "ISSUE-001",
      "status": "open | resolved | rejected | superseded",
      "severity": "high | medium | low | info",
      "category": "product_bug | test_bug | needs_confirmation | observation",
      "test_name": "稳定测试标识",
      "dimension": "api_resilience",
      "file_path": "app/example.py",
      "function_name": "function_name",
      "expected": "已确认的产品契约",
      "actual": "实际行为",
      "reproduce_steps": ["可执行步骤"],
      "suggested_fix": "建议方向",
      "evidence": "精简证据",
      "resolved_by": null,
      "resolution_evidence": null
    }
  ],
  "summary": "本轮结论"
}
```

## 门控语义

- `high`、`medium` 产品缺陷必须阻止合并。
- 关键维度存在任何失败时 Gate 1 失败。
- 测试套件异常必须计为失败，不能记为 0 项或跳过。
- 通过数量指“检查项/断言”，不宣称为相互独立的测试用例数。

## 隐私

不得把 `data/app.db` 或日志中的真实对话直接复制进测试、报告或 Git。需要真实场景覆盖时，只能使用获得授权且充分脱敏的数据，优先使用合成用例。

## 历史报告

2026-07-01 之前的文件使用旧结构，字段可能不一致，例如字符串形式的 `baseline.overall` 或单独的 `observations`。它们仅作历史记录，不能作为当前门控输入。
