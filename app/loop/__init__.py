"""
Loop 命令行入口

使用方法:
    python3 -m app.loop              # 运行单次迭代
    python3 -m app.loop --list-tasks # 查看任务队列
    python3 -m app.loop --memory     # 查看跨迭代记忆
    python3 -m app.loop --reset      # 重置 Loop 状态
"""

import argparse

from app.loop.state import LoopState
from app.loop.task_selector import TaskSelector
from app.loop.memory import LoopMemory
from app.loop.runner import LoopRunner


def _cmd_run() -> None:
    """运行单次迭代"""
    runner = LoopRunner()
    result = runner.run_once()
    if result.get("status") == "idle":
        print("✅ 无待处理任务，Loop 退出")
        return

    print(f"📝 结果: {result.get('status')}")
    if result.get("status") == "completed":
        task = result.get("task", {})
        print(f"   完成任务: [{task.get('id')}] {task.get('title', '')}")
    elif result.get("status") == "failed":
        print(f"   错误: {result.get('error', 'unknown')}")


def _cmd_list_tasks() -> None:
    """列出所有任务"""
    selector = TaskSelector()
    tasks = selector.list_all()

    if not tasks:
        print("📭 未找到任务，请确认 TODO.md 存在且有内容")
        return

    print(f"\n📋 共 {len(tasks)} 个任务\n")

    state = LoopState.load_from_disk()
    completed = set(state.completed_tasks)

    for t in tasks:
        status = "✅" if t.id in completed else "⏳"
        priority_label = {
            "in_progress": "【进行中】",
            "recent": "【近期】",
            "other": "",
        }.get(t.priority, "")
        print(f"  {status} [{t.id}] {priority_label}{t.title}")
        if t.description:
            print(f"      {t.description[:80]}{'...' if len(t.description) > 80 else ''}")

    pending = [t for t in tasks if t.id not in completed]
    print(f"\n⏳ 待处理: {len(pending)} | ✅ 已完成: {len(completed)}\n")


def _cmd_memory() -> None:
    """查看跨迭代记忆"""
    mem = LoopMemory()
    entries = mem.list_all(limit=50)

    if not entries:
        print("📭 暂无记忆")
        return

    print(f"\n💡 共 {len(entries)} 条记忆（显示最近 50 条）\n")

    type_emoji = {
        "decision": "🎯",
        "observation": "👁",
        "error": "❌",
        "pattern": "🔁",
    }

    for e in entries:
        emoji = type_emoji.get(e.type, "📝")
        from datetime import datetime
        dt = datetime.fromtimestamp(e.timestamp).strftime("%m-%d %H:%M")
        tags_str = f" [{', '.join(e.tags)}]" if e.tags else ""
        print(f"  {emoji} [{dt}] 迭代 #{e.iteration}{tags_str}")
        print(f"      {e.content[:100]}{'...' if len(e.content) > 100 else ''}")

    print()


def _cmd_reset() -> None:
    """重置 Loop 状态"""
    LoopState.reset()
    print("🔄 如需清空记忆，请运行: python3 -c 'from app.loop.memory import LoopMemory; LoopMemory().clear()'")


def main() -> None:
    parser = argparse.ArgumentParser(description="Loop 迭代运行器")
    parser.add_argument("--list-tasks", action="store_true", help="查看任务队列")
    parser.add_argument("--memory", action="store_true", help="查看跨迭代记忆")
    parser.add_argument("--reset", action="store_true", help="重置 Loop 状态")
    args = parser.parse_args()

    if args.list_tasks:
        _cmd_list_tasks()
    elif args.memory:
        _cmd_memory()
    elif args.reset:
        _cmd_reset()
    else:
        _cmd_run()


if __name__ == "__main__":
    main()
