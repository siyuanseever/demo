"""
Loop 任务选择器

解析 TODO.md，选择下一个最合适的任务。
使用容错解析，失败时降级为简单行匹配。
不改造 TODO.md 格式。
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Task:
    """结构化任务对象"""

    id: str
    title: str
    description: str
    priority: str
    source_file: str
    line_number: int


class TaskSelector:
    """任务选择器"""

    def __init__(self, todo_path: str = "TODO.md"):
        self.todo_path = Path(todo_path)
        self.tasks: list[Task] = []

    def select_next(self, state: Any | None = None) -> Task | None:
        """选择下一个最合适的任务"""
        self.tasks = self._parse_todo()

        if not self.tasks:
            return None

        completed_ids = set()
        if state and hasattr(state, "completed_tasks"):
            completed_ids = set(state.completed_tasks)

        # 过滤已完成的任务
        pending = [t for t in self.tasks if t.id not in completed_ids]
        if not pending:
            return None

        # 按优先级排序：进行中 > 近期 TODO > 其他
        priority_order = {"in_progress": 0, "recent": 1, "other": 2}
        pending.sort(key=lambda t: priority_order.get(t.priority, 2))

        return pending[0]

    def list_all(self) -> list[Task]:
        """列出所有解析出的任务"""
        return self._parse_todo()

    def _parse_todo(self) -> list[Task]:
        """解析 TODO.md，返回任务列表"""
        if not self.todo_path.exists():
            return []

        text = self.todo_path.read_text(encoding="utf-8")
        lines = text.splitlines()

        tasks: list[Task] = []
        current_section = "other"
        task_counter = 0

        for i, line in enumerate(lines, start=1):
            stripped = line.strip()

            # 识别章节
            if stripped.startswith("## "):
                section_title = stripped[3:].strip()
                if "进行中" in section_title:
                    current_section = "in_progress"
                elif "近期" in section_title or "TODO" in section_title.upper():
                    current_section = "recent"
                elif "已完成" in section_title:
                    current_section = "completed"
                else:
                    current_section = "other"
                continue

            # 识别列表项（以 - 或 * 或数字开头）
            if current_section == "completed":
                continue

            match = re.match(r"^\s*[-*]\s+(.+)$", stripped)
            if match:
                content = match.group(1).strip()
                # 跳过空内容或纯注释
                if not content or content.startswith("#"):
                    continue

                task_counter += 1
                task_id = f"todo_{current_section}_{task_counter}"

                # 提取子项描述（缩进的子列表）
                description = ""
                j = i
                while j < len(lines):
                    next_line = lines[j]
                    if next_line.startswith("    ") or next_line.startswith("\t"):
                        description += next_line.strip() + " "
                        j += 1
                    else:
                        break

                tasks.append(Task(
                    id=task_id,
                    title=content,
                    description=description.strip(),
                    priority=current_section,
                    source_file=str(self.todo_path),
                    line_number=i,
                ))

        return tasks
