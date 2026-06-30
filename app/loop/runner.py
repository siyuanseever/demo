"""
Loop single-iteration runner.

Implements a small Ralph-style loop:
1. reset in-memory context
2. load persisted state
3. select a task
4. load loop memory
5. execute the task through an injected hook
6. record result
7. persist updated state
"""

from __future__ import annotations

import time
from dataclasses import asdict
from typing import Any, Callable

from app.loop.memory import LoopMemory
from app.loop.state import LoopState, PlanStatus
from app.loop.task_selector import TaskSelector


TaskExecutor = Callable[[Any, PlanStatus, list[Any]], Any]


class LoopRunner:
    """Run one deterministic loop-engineering iteration."""

    def __init__(self) -> None:
        self.reset_context()
        self.task_executor: TaskExecutor | None = None

    def reset_context(self) -> None:
        self.state = LoopState.load_from_disk()
        self.plan_status = PlanStatus.read_plan_and_status()
        self.selector = TaskSelector()
        self.memory = LoopMemory()

    def set_task_executor(self, executor: TaskExecutor) -> None:
        self.task_executor = executor

    def run_once(self) -> dict[str, Any]:
        started_at = time.monotonic()
        self.reset_context()

        task = self.selector.select_next(self.state)
        if task is None:
            result = {
                "status": "idle",
                "message": "No pending task found.",
                "iteration_number": self.state.iteration_number,
            }
            self.state.last_action_result = result
            self.state.save_to_disk()
            return result

        memories = self.memory.list_all(limit=20)
        self.state.iteration_number += 1
        self.state.current_task_id = task.id

        try:
            executor_result = self._execute_task(task, self.plan_status, memories)
            result = {
                "status": "completed",
                "task": asdict(task),
                "result": executor_result,
                "elapsed_sec": round(time.monotonic() - started_at, 3),
                "iteration_number": self.state.iteration_number,
            }
            if task.id not in self.state.completed_tasks:
                self.state.completed_tasks.append(task.id)
            self.memory.add_memory(
                type="observation",
                content=f"Completed {task.id}: {task.title}",
                iteration=self.state.iteration_number,
                tags=["loop", "completed", task.priority],
            )
        except Exception as error:
            result = {
                "status": "failed",
                "task": asdict(task),
                "error": str(error),
                "elapsed_sec": round(time.monotonic() - started_at, 3),
                "iteration_number": self.state.iteration_number,
            }
            self.memory.add_memory(
                type="error",
                content=f"Failed {task.id}: {error}",
                iteration=self.state.iteration_number,
                tags=["loop", "error", task.priority],
            )
        finally:
            self.state.current_task_id = None
            self.state.last_action_result = result
            self.state.save_to_disk()

        return result

    def _execute_task(
        self,
        task: Any,
        plan_status: PlanStatus,
        memories: list[Any],
    ) -> Any:
        if self.task_executor is None:
            return {
                "message": "No task executor configured.",
                "task_title": getattr(task, "title", ""),
                "plan_chars": len(plan_status.plan_text),
                "status_chars": len(plan_status.status_text),
                "memory_count": len(memories),
            }
        return self.task_executor(task, plan_status, memories)
