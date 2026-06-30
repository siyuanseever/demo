"""
完整性检查框架自测

验证 CompletenessChecker 自身的四种检查能力是否正常工作。
"""

import tempfile
import os

from app.evaluation.accuracy import AccuracyTest


class CompletenessFrameworkAccuracyTest(AccuracyTest):
    """completeness 框架自测"""

    def __init__(self):
        super().__init__("completeness_framework", "evaluation.completeness")

    def run(self):
        from app.evaluation.completeness import CompletenessChecker

        with tempfile.TemporaryDirectory() as tmpdir:
            checker = CompletenessChecker(tmpdir)

            # 1. 文件存在性检查 —— 存在的文件
            test_file = os.path.join(tmpdir, "test_exists.py")
            with open(test_file, "w") as f:
                f.write("# test")
            passed = checker.check_file_exists("test_exists.py", "测试文件")
            self.assert_true("file_exists_pass", passed, "已创建的文件应检测为存在")

            # 2. 文件存在性检查 —— 不存在的文件
            passed = checker.check_file_exists("not_exists.py", "不存在的文件")
            self.assert_true("file_exists_fail", not passed, "不存在的文件应检测为缺失")

            # 3. 模块可导入性 —— 已安装的标准库
            passed = checker.check_module_importable("json")
            self.assert_true("module_importable_pass", passed, "json 模块应可导入")

            # 4. 模块可导入性 —— 不存在的模块
            passed = checker.check_module_importable("nonexistent_module_xyz")
            self.assert_true("module_importable_fail", not passed, "不存在的模块应导入失败")

            # 5. AST 定义检查 —— 正确的函数和类
            ast_file = os.path.join(tmpdir, "ast_test.py")
            with open(ast_file, "w") as f:
                f.write("def foo(): pass\nclass Bar: pass\n")
            passed = checker.check_ast_definitions(
                "ast_test.py",
                expected_functions=["foo"],
                expected_classes=["Bar"],
            )
            self.assert_true("ast_definitions_pass", passed, "AST 应正确识别函数和类")

            # 6. AST 定义检查 —— 缺失的函数
            passed = checker.check_ast_definitions(
                "ast_test.py",
                expected_functions=["missing_func"],
            )
            self.assert_true("ast_definitions_fail", not passed, "缺失的函数应被检测到")

            # 7. AST 定义检查 —— 不存在的文件
            passed = checker.check_ast_definitions("no_such_file.py")
            self.assert_true("ast_definitions_no_file", not passed, "不存在的文件应失败")

            # 8. 依赖检查 —— 完整依赖
            passed = checker.check_dependencies("test_mod", ["json", "os"])
            self.assert_true("dependencies_pass", passed, "标准库依赖应完整")

            # 9. 依赖检查 —— 缺失依赖
            passed = checker.check_dependencies("test_mod", ["json", "nonexistent_dep_xyz"])
            self.assert_true("dependencies_fail", not passed, "缺失的依赖应被检测到")

            # 10. summary() 输出结构验证
            summary = checker.summary()
            self.assert_true("summary_has_total", "total" in summary)
            self.assert_true("summary_has_passed", "passed" in summary)
            self.assert_true("summary_has_pass_rate", "pass_rate" in summary)
            self.assert_true("summary_has_details", "details" in summary)
            self.assert_true("summary_total_gt_0", summary["total"] > 0)

        return self.results


def get_completeness_tests() -> list[AccuracyTest]:
    """返回完整性框架自测实例"""
    return [CompletenessFrameworkAccuracyTest()]
