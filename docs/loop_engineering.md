# Loop Engineering Plan

这个项目里的 loop engineering 先按最小闭环实现，不先做复杂平台。

## Roles

- Maker：在独立 worktree/branch 里实现一个明确改动。
- Checker：只做验证和审查，不继续扩大需求。
- Merger：根据 checker 报告、diff 风险和人工判断决定是否合并。

## Checker Layers

1. Contract checker：检查后端事件顺序、数据结构、数据库写入数量等不应该破坏的契约。
2. UI checker：检查真实渲染后的前端脚本、关键 DOM/交互是否可运行。
3. Quality checker：用少量稳定样例检查产品行为，例如 intent route 是否符合预期。

当前入口：

```bash
python3 -m app.evaluation.check_loop
```

输出包含 `confidence` 和 `merge_recommendation`：

- `confidence == 1.0`：可以作为自动合并候选，但仍要看 diff 范围。
- `confidence < 1.0`：需要人工 review，不能自动合并。

## Worktree Flow

建议后续流程：

1. 从主工作区创建 maker worktree，例如 `../demo-maker-intent-sse`。
2. Maker 只在该 worktree 修改代码。
3. Checker 在 maker worktree 运行 `python3 -m app.evaluation.check_loop` 和必要的额外检查。
4. Checker 写下结论：通过项、失败项、风险、建议。
5. Merger 决定 cherry-pick、merge branch，或要求 maker 继续修。

## Status Files

后续可以加两个轻量文件：

- `STATUS.md`：记录当前 loop、分支、checker 结果、merge 建议。
- `TODO.md`：继续记录产品和工程任务，不记录每次循环日志。

暂时不自动写 `STATUS.md`，避免每次 checker 运行造成无意义文件 churn。
