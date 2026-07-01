# Checker / Fixer 自动化编排

本文件定义调度和队列规则。它不是第三个智能 Agent；调度器只负责定时、互斥、传递 run ID 和维护 cursor，不做代码判断。

## 推荐频率

时区统一为 `Asia/Shanghai`：

| 任务 | 时间 | 说明 |
|---|---|---|
| Checker | 02:00、08:00、14:00、20:00 | 每 6 小时增量审查、写测试、运行 Harness |
| Fixer | 05:00 | 每天批量消费上次 Fixer 之后的所有 Checker run |

这样 Fixer 每次通常消费前一天 08:00、14:00、20:00 和当天 02:00 四轮结果；08:00 Checker 会优先验证 05:00 Fixer 的修复。

高风险 issue 可以立即通知用户，但默认不额外触发 Fixer，避免并发修改。若以后需要紧急修复，应由确定性调度器增加一次性 Fixer 任务，而不是新增第三个 LLM Agent。

## 持久集成分支

自动化使用一个串行分支和一个固定 worktree：

- branch：`automation/quality-loop`
- worktree：由调度器配置，不能是用户当前主工作区

Checker 和 Fixer轮流在该分支提交：

```text
产品基线
  → Checker 测试 commit
  → Checker 测试 commit
  → Fixer 产品 commit
  → Checker 复验/测试 commit
```

角色隔离由每个 commit 的路径白名单保证，而不是为每轮创建互不相连的 branch。这样一天四轮测试不会产生四条无法汇合的分支。

同步主分支时只允许：

- 自动化 worktree 干净；
- 能够 fast-forward 或由用户批准普通 merge；
- 出现冲突时停止并报告，不自动 rebase、不覆盖用户修改。

## 互斥

Checker 与 Fixer 不得并发。调度器启动任务前获取独占锁；锁已存在时，本轮写入 `skipped_due_to_lock` 调度记录并退出。

建议锁：

`/private/tmp/xiaodongwu-quality-loop.lock`

锁必须包含启动时间、任务类型和进程标识，并设置陈旧锁处理策略。Agent 自己不得强行删除无法确认归属的锁。

## 目录和队列

```text
eval_reports/agent_handoffs/
├── checker/
│   └── YYYYMMDD/<checker_run_id>/
├── fixer/
│   └── YYYYMMDD/<fixer_run_id>/
├── indexes/
│   ├── checker_runs.jsonl
│   └── fixer_runs.jsonl
├── state/
│   ├── checker_state.json
│   └── fixer_state.json
├── LATEST_CHECKER.json
└── LATEST_FIXER.json
```

索引采用 append-only JSONL，每行只存元数据和报告路径，不复制完整报告。写报告顺序：

1. 在 run 目录写临时文件；
2. 原子 rename 为最终报告；
3. append 对应 index；
4. 原子更新角色自己的 state；
5. 原子更新 `LATEST_*`。

`LATEST_*` 只供人快速查看，不能作为自动消费队列。

## Cursor 规则

Checker 拥有：

- `last_reviewed_commit`
- `processed_fixer_run_ids`
- `last_checker_run_id`

Fixer 拥有：

- `processed_checker_run_ids`
- `last_fixer_run_id`

Fixer 每天读取 `checker_runs.jsonl`，选择所有不在 `processed_checker_run_ids` 中的合法 run。所有被扫描的 run——包括 `no_change` 和 `no_issues`——都必须进入 processed 列表，避免第二天重复读取。

Checker 每轮读取 `fixer_runs.jsonl`，只验证不在 `processed_fixer_run_ids` 中的 Fixer batch。验证完成后才推进 cursor。

## Fixer 批处理

Fixer 将多轮 Checker 报告合并为一个 batch：

1. 按 `issue_id` 聚合；
2. 同一 issue 只处理一次；
3. 使用生成时间最新的状态和证据；
4. 保留所有 `source_checker_run_ids`；
5. 最新状态为 `resolved`、`observation` 或 `needs_human` 时，不自动修产品；
6. 多个 issue 共享根因时可以一次修复，但必须逐项回执。

Fixer 完成后，一次性把本批次所有已扫描 Checker run 写入自己的 processed cursor。若任务中途失败，不推进 cursor，下次安全重试。

## 报告层次

- Checker：每 6 小时一份 run 报告，用于追踪增量和独立复验。
- Fixer：每天一份 batch 回执，是当天给用户和下一轮 Checker 的聚合摘要。
- 不要求第三个 Agent 再生成日报；Fixer batch HTML 即每日处理报告。

