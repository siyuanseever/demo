# Loop 基础设施

实现 Ralph 技术的 Loop 迭代运行系统。

## 设计原则

- **每次迭代完全重置上下文**：不保留上次实例状态
- **所有状态从磁盘读取**：启动时唯一信息来源是磁盘文件
- **完成任务后立即退出**：不等待下一轮，由外部调度器决定是否再次启动
- **记忆存储在磁盘**：不依赖上下文窗口，跨 Session 持久化

## 模块说明

| 文件 | 职责 |
|------|------|
| `state.py` | LoopState 数据模型，读写 `data/loop_state.json`；PlanStatus 读取用户维护的 `plan.md` 和 `status.md` |
| `task_selector.py` | 解析 `TODO.md`，按优先级（进行中 > 近期 TODO > 其他）选择下一个任务 |
| `memory.py` | 跨迭代记忆的持久化存储，支持关键词/类型/标签检索，自动归档旧记录 |
| `runner.py` | 单次迭代的完整运行流程：重置 -> 读盘 -> 选任务 -> 加载记忆 -> 执行 -> 记录 -> 写盘 -> 退出 |
| `__init__.py` | CLI 入口：run / list-tasks / memory / reset |

## 状态文件

| 文件 | 维护者 | 说明 |
|------|--------|------|
| `plan.md` | 用户 | 当前阶段计划 |
| `status.md` | 用户 | 当前进度状态 |
| `data/loop_state.json` | 自动 | Loop 运行状态（迭代次数、已完成任务、上次结果） |
| `data/loop_memory.jsonl` | 自动 | 跨迭代记忆（最近 50 条） |
| `data/loop_memory_archive.jsonl` | 自动 | 归档记忆（超过 50 条的旧记录） |

## 使用方式

```bash
# 运行单次迭代
python3 -m app.loop

# 查看任务队列
python3 -m app.loop --list-tasks

# 查看跨迭代记忆
python3 -m app.loop --memory

# 重置 Loop 状态
python3 -m app.loop --reset
```

## 与 Harness 门控的衔接

Loop 单次迭代完成后：

1. 自动触发 Gate 0（`python3 -m compileall app`）
2. 若 Gate 0 失败，将错误写入 `loop_memory`（type="error"），下次迭代优先修复
3. Gate 1 由开发者手动或通过 CI 触发（`python3 -m app.evaluation.runner`）

## 扩展任务执行

默认情况下 Loop 只分发任务（返回 dispatched 状态）。要接入具体业务逻辑：

```python
from app.loop.runner import LoopRunner

def my_executor(context):
    task = context["task"]
    # 执行具体任务...
    return {"success": True, "summary": "完成"}

runner = LoopRunner()
runner.set_task_executor(my_executor)
runner.run_single_iteration()
```
