"""
代码完整性评估模块

检查模块接口完整性、依赖完整性、关键文件存在性。
支持 AST 级别的函数/类定义扫描。
"""

import ast
import os
import sys
import inspect
import importlib
import pkgutil
from pathlib import Path
from typing import Any
from dataclasses import dataclass


@dataclass
class CompletenessResult:
    module_name: str
    check_type: str
    passed: bool
    message: str
    detail: dict = None

    def __post_init__(self):
        if self.detail is None:
            self.detail = {}


class CompletenessChecker:
    """代码完整性检查器"""

    def __init__(self, project_root: str | None = None):
        self.project_root = Path(project_root) if project_root else Path.cwd()
        self.results: list[CompletenessResult] = []

    def check_file_exists(self, relative_path: str, description: str = "") -> bool:
        """检查关键文件是否存在"""
        full_path = self.project_root / relative_path
        passed = full_path.exists()
        self.results.append(CompletenessResult(
            module_name="project",
            check_type="file_exists",
            passed=passed,
            message=f"{'存在' if passed else '缺失'}: {relative_path}" + (f" ({description})" if description else ""),
            detail={"path": str(full_path), "expected": relative_path},
        ))
        return passed

    def check_module_importable(self, module_name: str) -> bool:
        """检查模块是否可以导入"""
        try:
            importlib.import_module(module_name)
            self.results.append(CompletenessResult(
                module_name=module_name,
                check_type="importable",
                passed=True,
                message=f"模块 {module_name} 可正常导入",
            ))
            return True
        except Exception as e:
            self.results.append(CompletenessResult(
                module_name=module_name,
                check_type="importable",
                passed=False,
                message=f"模块 {module_name} 导入失败: {e}",
                detail={"error": str(e)},
            ))
            return False

    def check_class_methods(self, module_name: str, class_name: str, expected_methods: list[str]) -> bool:
        """检查类是否包含预期的方法"""
        try:
            module = importlib.import_module(module_name)
            cls = getattr(module, class_name)
            actual_methods = {m for m in dir(cls) if not m.startswith("_") or m in ("__init__",)}
            missing = [m for m in expected_methods if m not in actual_methods]
            passed = len(missing) == 0
            self.results.append(CompletenessResult(
                module_name=f"{module_name}.{class_name}",
                check_type="class_methods",
                passed=passed,
                message=f"{'完整' if passed else f'缺失 {len(missing)} 个方法: {missing}'}",
                detail={"expected": expected_methods, "actual": sorted(actual_methods), "missing": missing},
            ))
            return passed
        except Exception as e:
            self.results.append(CompletenessResult(
                module_name=f"{module_name}.{class_name}",
                check_type="class_methods",
                passed=False,
                message=f"检查失败: {e}",
            ))
            return False

    def check_ast_definitions(self, file_path: str, expected_functions: list[str] | None = None, expected_classes: list[str] | None = None) -> bool:
        """通过 AST 检查 Python 文件中是否包含预期的函数/类定义"""
        full_path = self.project_root / file_path
        if not full_path.exists():
            self.results.append(CompletenessResult(
                module_name=file_path,
                check_type="ast_definitions",
                passed=False,
                message=f"文件不存在: {file_path}",
            ))
            return False

        try:
            source = full_path.read_text(encoding="utf-8")
            tree = ast.parse(source)
            actual_functions = [node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]
            actual_classes = [node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)]

            missing_funcs = [f for f in (expected_functions or []) if f not in actual_functions]
            missing_classes = [c for c in (expected_classes or []) if c not in actual_classes]
            passed = len(missing_funcs) == 0 and len(missing_classes) == 0

            self.results.append(CompletenessResult(
                module_name=file_path,
                check_type="ast_definitions",
                passed=passed,
                message=f"{'完整' if passed else f'缺失函数: {missing_funcs}, 缺失类: {missing_classes}'}",
                detail={
                    "functions": actual_functions,
                    "classes": actual_classes,
                    "missing_functions": missing_funcs,
                    "missing_classes": missing_classes,
                },
            ))
            return passed
        except SyntaxError as e:
            self.results.append(CompletenessResult(
                module_name=file_path,
                check_type="ast_definitions",
                passed=False,
                message=f"语法错误: {e}",
                detail={"error": str(e)},
            ))
            return False

    def check_dependencies(self, module_name: str, required_modules: list[str]) -> bool:
        """检查模块依赖是否可导入"""
        missing = []
        for req in required_modules:
            try:
                importlib.import_module(req)
            except ImportError:
                missing.append(req)
        passed = len(missing) == 0
        self.results.append(CompletenessResult(
            module_name=module_name,
            check_type="dependencies",
            passed=passed,
            message=f"{'依赖完整' if passed else f'缺失依赖: {missing}'}",
            detail={"required": required_modules, "missing": missing},
        ))
        return passed

    def summary(self) -> dict[str, Any]:
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        by_module: dict[str, list[CompletenessResult]] = {}
        for r in self.results:
            by_module.setdefault(r.module_name, []).append(r)

        return {
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate": round(passed / total, 4) if total else 0,
            "by_module": {
                mod: {
                    "total": len(rs),
                    "passed": sum(1 for r in rs if r.passed),
                    "pass_rate": round(sum(1 for r in rs if r.passed) / len(rs), 4) if rs else 0,
                }
                for mod, rs in by_module.items()
            },
            "details": [
                {
                    "module": r.module_name,
                    "check_type": r.check_type,
                    "passed": r.passed,
                    "message": r.message,
                }
                for r in self.results
            ],
        }
