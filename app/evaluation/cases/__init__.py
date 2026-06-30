"""
评估用例加载器

提供 cases.yaml 和 rubric.md 的统一加载接口。
"""

import json
from pathlib import Path
from typing import Any


_CASES_DIR = Path(__file__).parent


def load_yaml_cases() -> list[dict[str, Any]]:
    """加载评估用例列表"""
    cases_path = _CASES_DIR / "cases.yaml"
    if not cases_path.exists():
        return []

    # 简单 YAML 列表解析（cases.yaml 是顶层列表格式）
    text = cases_path.read_text(encoding="utf-8")
    cases: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    for line in text.splitlines():
        stripped = line.rstrip()
        if not stripped:
            continue

        # 顶级列表项以 "- id:" 开头
        if stripped.startswith("- id:"):
            if current is not None:
                cases.append(current)
            current = {"id": stripped.split(":", 1)[1].strip()}
        elif current is not None and stripped.startswith("  "):
            # 子字段，格式为 "  key: value"
            key_val = stripped.strip()
            if ":" in key_val:
                key, val = key_val.split(":", 1)
                current[key.strip()] = val.strip()

    if current is not None:
        cases.append(current)

    return cases


def load_rubric() -> dict[str, Any]:
    """加载评分标准文档，返回结构化数据"""
    rubric_path = _CASES_DIR / "rubric.md"
    if not rubric_path.exists():
        return {}

    text = rubric_path.read_text(encoding="utf-8")
    result: dict[str, Any] = {"dimensions": [], "failure_types": []}

    section = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        if "评分" in stripped and "-" in stripped:
            section = "dimensions"
            continue
        if "失败类型" in stripped:
            section = "failure_types"
            continue

        if section == "dimensions" and stripped.startswith("-"):
            # 格式: "- 维度名：范围"
            item = stripped[1:].strip()
            if "：" in item:
                name, scale = item.split("：", 1)
                result["dimensions"].append({"name": name.strip(), "scale": scale.strip()})
            else:
                result["dimensions"].append({"name": item, "scale": ""})

        elif section == "failure_types" and stripped.startswith("-"):
            result["failure_types"].append(stripped[1:].strip())

    return result


def cases_to_jsonl() -> str:
    """将 cases 转换为 JSON Lines 格式字符串"""
    cases = load_yaml_cases()
    lines = [json.dumps(c, ensure_ascii=False) for c in cases]
    return "\n".join(lines)
