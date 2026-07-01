# Evaluation Harness

本目录提供本地、可重复的工程检查。默认使用临时数据库和 FakeClient，不调用真实模型 API。

## 标准命令

```bash
# Gate 0：Python 语法
python3 -m compileall app

# Web/JS/SSE 契约
python3 -m app.evaluation.check_sse_stream

# 分层快速检查
python3 -m app.evaluation.check_harness

# Gate 1：完整综合评估
python3 -m app.evaluation.runner

# Gate 1 失败后的诊断
python3 -m app.evaluation.diagnose

# 生成体验评估待评分表
python3 -m app.evaluation.manual_eval
```

## Gate 1 判定

Runner 只有同时满足以下条件才返回退出码 0：

- 综合通过率 >= 95%；
- `accuracy`、`robustness`、`completeness`、`functional`、`api_resilience`、`framework` 均为 100%；
- 没有测试套件执行异常。

套件异常会生成一个明确失败项，不会被折算成 0 项而产生假通过。

当前基线（2026-07-01）为 236/236。

## 评估维度

| 维度 | 内容 |
|---|---|
| `accuracy` | 核心函数与契约输出 |
| `robustness` | 异常输入、并发、模型失败降级 |
| `completeness` | 文件、导入、AST 定义和依赖 |
| `reply_speed` | FakeClient 下的本地路径耗时回归，不代表真实 API SLA |
| `reply_quality` | 本地启发式质量检查，不替代人工体验判断 |
| `functional` | 会话、路由、持久化等集成行为 |
| `api_resilience` | 流式 JSON、数据边界和 UI 相关边界 |
| `framework` | Evaluation、Prompt evaluator、cases 和 rubric 自测 |

Runner 还记录 benchmark 和进程指标，但它们不计入检查项总数。

## 报告

每次 Runner 执行生成：

- `eval_reports/eval_report_{timestamp}.json`
- `eval_reports/eval_report_{timestamp}.html`

JSON 的 `overall.gate_passed` 是门控结论；不要只读取总体百分比。失败后运行 `diagnose`，它会检查全部八个维度。

观察建议必须放在 `observations` 中，不计入通过率。静态代码偏好、日志增强建议和未确认产品契约不能硬编码成失败测试。

## Prompt 与体验审查

`/prompt-inspector` 用于查看 Prompt JSON 有效率、耗时和 token。相关结构化调用的 JSON 有效率目标为 >=95%，但当前没有独立 CLI 门控，汇报时必须写明样本范围。

`manual_eval` 只生成待评分表。报告中 `review_status=pending_manual_review`、case 分数为空时，不构成体验审查通过证据。

## 新增测试

新增检查必须：

1. 验证可观察行为，而不是复制实现公式；
2. 写明稳定产品契约；
3. 注册到 Runner 对应套件；
4. 失败时返回非零退出码；
5. 不读取或复制真实私密对话数据；
6. 将设计建议作为 observation，而不是 product bug。

Runner 自身的集成测试不能递归注册进 Runner。需要修改 Runner 时，应额外检查报告结构、退出码和失败套件行为。
