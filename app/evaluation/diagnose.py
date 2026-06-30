"""
评估失败项自动诊断工具

运行方式:
    python3 -m app.evaluation.diagnose

功能:
1. 读取最新生成的 JSON 评估报告
2. 逐个分析每个失败项
3. 自动分类: 产品代码缺陷 / 测试代码缺陷 / 待人工确认
4. 输出可直接复制给 agent 的修复指令
"""

import json
import glob
import os
from pathlib import Path
from typing import Any


def find_latest_report(output_dir: str = "eval_reports") -> str | None:
    """查找最新的 JSON 报告文件"""
    pattern = os.path.join(output_dir, "eval_report_*.json")
    files = glob.glob(pattern)
    if not files:
        return None
    return max(files, key=os.path.getmtime)


def classify_failure(failure: dict, dimension: str) -> dict[str, Any]:
    """
    根据失败信息自动分类。

    判断逻辑:
    - 如果 exception 包含被测代码的文件路径 → 产品代码缺陷
    - 如果 expected 和 actual 差异明显是功能遗漏 → 产品代码缺陷
    - 如果 exception 在测试框架内 → 测试代码缺陷
    """
    result = {
        "test_name": failure.get("test_name", "unknown"),
        "module": failure.get("module", "unknown"),
        "dimension": dimension,
        "classification": "待人工确认",
        "reason": "",
        "action": "",
        "is_product_bug": False,
        "details": failure,
    }

    exception = failure.get("exception", "")
    message = failure.get("message", "")
    expected = failure.get("expected")
    actual = failure.get("actual")

    # 规则 1: 异常堆栈指向产品代码文件路径
    product_paths = ["app/agents/", "app/memory/", "app/llm/", "app/knowledge/", "app/characters/"]
    stack_points_to_product = any(p in exception for p in product_paths)

    # 规则 2: 准确率测试中，expected=True, actual=False → 产品功能未实现
    accuracy_mismatch = dimension in ("accuracy", "准确率") and expected is True and actual is False

    if dimension in ("accuracy", "准确率"):
        if accuracy_mismatch:
            # 进一步判断是否是关键词匹配类的问题
            if "crisis" in failure.get("test_name", "").lower() or "agents.safety" == failure.get("module", ""):
                result["classification"] = "产品代码缺陷"
                result["is_product_bug"] = True
                result["reason"] = f"`detect_crisis()` 对输入 '{failure.get('test_name', '')}' 返回了 False，但预期应为 True。说明 `CRISIS_KEYWORDS` 缺少该表达。"
                result["action"] = f"在 `app/agents/safety.py` 的 `CRISIS_KEYWORDS` 中添加对应关键词。"
            else:
                result["classification"] = "产品代码缺陷"
                result["is_product_bug"] = True
                result["reason"] = f"函数返回值与预期不符。期望: {expected}, 实际: {actual}。"
                result["action"] = f"检查 {failure.get('module', '')} 模块中对应函数的实现逻辑。"
        elif "exception" in message.lower() or exception:
            result["classification"] = "产品代码缺陷"
            result["is_product_bug"] = True
            result["reason"] = f"函数执行时抛出异常: {message}"
            result["action"] = f"在 {failure.get('module', '')} 中添加异常处理。"
        else:
            result["classification"] = "待人工确认"
            result["reason"] = f"期望值与实际值不匹配。期望: {expected}, 实际: {actual}。"
            result["action"] = "确认是产品逻辑错误还是测试断言写错。"

    elif dimension in ("robustness", "鲁棒性"):
        if stack_points_to_product:
            # 提取异常类型
            exc_type = "未知异常"
            if ":" in message:
                exc_type = message.split(":")[0].replace("未预期异常: ", "").strip()

            result["classification"] = "产品代码缺陷"
            result["is_product_bug"] = True
            result["reason"] = f"边界条件测试触发未捕获异常 ({exc_type})。函数在异常输入下直接崩溃，缺少保护逻辑。"
            result["action"] = f"在 {failure.get('module', '')} 对应函数中添加 try-except 保护。"
        elif "测试运行异常" in message:
            result["classification"] = "测试代码缺陷"
            result["reason"] = "测试框架本身执行出错，可能是参数传递错误或环境配置问题。"
            result["action"] = "检查测试用例代码。"
        else:
            result["classification"] = "待人工确认"
            result["reason"] = f"鲁棒性测试失败: {message}"
            result["action"] = "人工确认失败根因。"

    elif dimension in ("completeness", "完整性"):
        result["classification"] = "产品代码缺陷"
        result["is_product_bug"] = True
        result["reason"] = f"完整性检查失败: {message}"
        result["action"] = "补充缺失的文件、方法或依赖。"

    return result


def print_diagnosis(report_path: str) -> None:
    """打印诊断报告"""
    with open(report_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    print("=" * 70)
    print("🔍 评估失败项自动诊断报告")
    print("=" * 70)
    print(f"报告文件: {report_path}")
    print(f"生成时间: {data.get('generated_at', 'unknown')}")
    print()

    overall = data.get("overall", {})
    total_failed = overall.get("total_failed", 0)

    if total_failed == 0:
        print("✅ 本次评估无失败项，所有测试全部通过！")
        return

    print(f"发现 {total_failed} 个失败项，开始逐个分析...")
    print()

    # 收集所有失败项
    failures = []

    for detail in data.get("accuracy", {}).get("details", []):
        if not detail.get("passed", True):
            failures.append(classify_failure(detail, "准确率"))

    for detail in data.get("robustness", {}).get("details", []):
        if not detail.get("passed", True):
            failures.append(classify_failure(detail, "鲁棒性"))

    for detail in data.get("completeness", {}).get("details", []):
        if not detail.get("passed", True):
            failures.append(classify_failure(detail, "完整性"))

    # 按分类分组
    product_bugs = [f for f in failures if f["is_product_bug"]]
    test_bugs = [f for f in failures if f["classification"] == "测试代码缺陷"]
    uncertain = [f for f in failures if f["classification"] == "待人工确认"]

    # 打印产品代码缺陷
    if product_bugs:
        print(f"\n{'=' * 70}")
        print(f"🐛 产品代码缺陷 ({len(product_bugs)} 项) —— 需要修复源代码")
        print(f"{'=' * 70}")
        for i, f in enumerate(product_bugs, 1):
            print(f"\n  [{i}] 测试名称: {f['test_name']}")
            print(f"      所属模块: {f['module']}")
            print(f"      评估维度: {f['dimension']}")
            print(f"      失败原因: {f['reason']}")
            print(f"      修复建议: {f['action']}")
            # 输出可直接给 agent 的指令
            print(f"\n      💬 给 agent 的指令模板:")
            print(f"         \"{f['action']} 相关失败测试: {f['test_name']}\"")

    # 打印测试代码缺陷
    if test_bugs:
        print(f"\n{'=' * 70}")
        print(f"🔧 测试代码缺陷 ({len(test_bugs)} 项) —— 需要修复测试用例")
        print(f"{'=' * 70}")
        for i, f in enumerate(test_bugs, 1):
            print(f"\n  [{i}] 测试名称: {f['test_name']}")
            print(f"      失败原因: {f['reason']}")
            print(f"      修复建议: {f['action']}")

    # 打印待确认项
    if uncertain:
        print(f"\n{'=' * 70}")
        print(f"❓ 待人工确认 ({len(uncertain)} 项)")
        print(f"{'=' * 70}")
        for i, f in enumerate(uncertain, 1):
            print(f"\n  [{i}] 测试名称: {f['test_name']}")
            print(f"      所属模块: {f['module']}")
            print(f"      失败原因: {f['reason']}")
            print(f"      调试建议: {f['action']}")

    # 汇总
    print(f"\n{'=' * 70}")
    print("📊 诊断汇总")
    print(f"{'=' * 70}")
    print(f"   产品代码缺陷: {len(product_bugs)} 项 → 修复源代码")
    print(f"   测试代码缺陷: {len(test_bugs)} 项 → 修复测试用例")
    print(f"   待人工确认:   {len(uncertain)} 项 → 人工判断")
    print()

    if product_bugs:
        print("💡 你可以直接复制以下指令给 agent 修复产品缺陷:")
        print()
        for f in product_bugs:
            print(f"   - {f['action']} (失败测试: {f['test_name']})")
        print()


def main():
    report = find_latest_report()
    if not report:
        print("❌ 未找到评估报告。请先运行: python3 -m app.evaluation.runner")
        return
    print_diagnosis(report)


if __name__ == "__main__":
    main()
