"""
Loop 状态模型与读写

自动维护 data/loop_state.json，支持读取用户维护的 plan.md 和 status.md。
状态文件损坏时自动重置。
"""

import json
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any


_STATE_PATH = Path("data/loop_state.json")


@dataclass
class LoopState:
    """Loop 运行状态"""

    iteration_number: int = 0
    current_task_id: str | None = None
    completed_tasks: list[str] = field(default_factory=list)
    context_summary: str = ""
    last_action_result: dict[str, Any] = field(default_factory=dict)

    def save_to_disk(self) -> None:
        """保存状态到磁盘"""
        _STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        _STATE_PATH.write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    @staticmethod
    def load_from_disk() -> "LoopState":
        """从磁盘加载状态，损坏时自动重置"""
        if not _STATE_PATH.exists():
            return LoopState()

        try:
            data = json.loads(_STATE_PATH.read_text(encoding="utf-8"))
            return LoopState(
                iteration_number=data.get("iteration_number", 0),
                current_task_id=data.get("current_task_id"),
                completed_tasks=data.get("completed_tasks", []),
                context_summary=data.get("context_summary", ""),
                last_action_result=data.get("last_action_result", {}),
            )
        except (json.JSONDecodeError, KeyError, TypeError):
            print("⚠️ Loop 状态文件损坏，自动重置")
            return LoopState()

    @staticmethod
    def reset() -> None:
        """重置状态文件"""
        if _STATE_PATH.exists():
            _STATE_PATH.unlink()
        print("✅ Loop 状态已重置")


@dataclass
class PlanStatus:
    """用户维护的计划与状态"""

    plan_text: str = ""
    status_text: str = ""

    @staticmethod
    def read_plan_and_status(plan_path: str = "plan.md", status_path: str = "status.md") -> "PlanStatus":
        """读取用户维护的 plan.md 和 status.md"""
        plan_file = Path(plan_path)
        status_file = Path(status_path)

        plan_text = plan_file.read_text(encoding="utf-8") if plan_file.exists() else ""
        status_text = status_file.read_text(encoding="utf-8") if status_file.exists() else ""

        return PlanStatus(plan_text=plan_text, status_text=status_text)
