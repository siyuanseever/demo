"""
报告生成模块

生成 JSON 和 HTML 两种格式的评估报告，包含可视化图表。
"""

import json
import time
from datetime import datetime
from pathlib import Path
from typing import Any


class ReportGenerator:
    """评估报告生成器"""

    def __init__(self, output_dir: str = "eval_reports"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def save_json(self, data: dict[str, Any], filename: str | None = None) -> str:
        """保存 JSON 报告"""
        if filename is None:
            filename = f"eval_report_{int(time.time())}.json"
        path = self.output_dir / filename
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        return str(path)

    def save_html(self, data: dict[str, Any], filename: str | None = None) -> str:
        """生成 HTML 报告"""
        if filename is None:
            filename = f"eval_report_{int(time.time())}.html"
        path = self.output_dir / filename

        html = self._build_html(data)
        path.write_text(html, encoding="utf-8")
        return str(path)

    def _build_html(self, data: dict) -> str:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        overall = data.get("overall", {})
        timer_summary = data.get("timer_summary", [])
        metrics_summary = data.get("metrics_summary", {})
        accuracy = data.get("accuracy", {})
        robustness = data.get("robustness", {})
        completeness = data.get("completeness", {})

        def _card(title: str, content: str, color: str = "#3498db") -> str:
            return f"""
            <div style="background:#fff;border-radius:8px;padding:20px;margin:12px 0;box-shadow:0 2px 8px rgba(0,0,0,0.08);border-left:4px solid {color};">
                <h3 style="margin:0 0 12px 0;color:{color};font-size:16px;">{title}</h3>
                {content}
            </div>
            """

        def _badge(label: str, value: str, ok: bool = True) -> str:
            color = "#27ae60" if ok else "#e74c3c"
            return f'<span style="background:{color};color:#fff;padding:4px 10px;border-radius:12px;font-size:13px;margin-right:8px;">{label}: {value}</span>'

        def _table(headers: list[str], rows: list[list[str]]) -> str:
            th = "".join(f"<th style='padding:10px;border-bottom:2px solid #eee;text-align:left;background:#f8f9fa;'>{h}</th>" for h in headers)
            trs = ""
            for row in rows:
                tds = "".join(f"<td style='padding:10px;border-bottom:1px solid #eee;'>{c}</td>" for c in row)
                trs += f"<tr>{tds}</tr>"
            return f"<table style='width:100%;border-collapse:collapse;font-size:14px;'>{th}{trs}</table>"

        timer_rows = []
        for s in timer_summary:
            timer_rows.append([
                s.get("name", ""),
                str(s.get("count", 0)),
                f"{s.get('avg_sec', 0):.4f}",
                f"{s.get('min_sec', 0):.4f}",
                f"{s.get('max_sec', 0):.4f}",
                f"{s.get('p95_sec', 0):.4f}",
                f"{s.get('p99_sec', 0):.4f}",
            ])

        accuracy_mods = accuracy.get("by_module", {})
        accuracy_rows = [[mod, str(v["total"]), str(v["passed"]), f"{v['pass_rate']*100:.1f}%"] for mod, v in accuracy_mods.items()]

        robust_mods = robustness.get("by_module", {})
        robust_rows = [[mod, str(v["total"]), str(v["passed"]), f"{v['pass_rate']*100:.1f}%"] for mod, v in robust_mods.items()]

        complete_mods = completeness.get("by_module", {})
        complete_rows = [[mod, str(v["total"]), str(v["passed"]), f"{v['pass_rate']*100:.1f}%"] for mod, v in complete_mods.items()]

        metrics_gauges = metrics_summary.get("gauges", {})
        metrics_html = "<div style='display:flex;flex-wrap:wrap;gap:12px;'>"
        for k, v in metrics_gauges.items():
            metrics_html += f"<div style='background:#f0f4f8;padding:10px 16px;border-radius:6px;'><b>{k}</b>: {v:.2f}</div>"
        metrics_html += "</div>"

        overall_content = f"""
        <div style="display:flex;flex-wrap:wrap;gap:10px;margin-bottom:10px;">
            {_badge("总测试数", str(overall.get("total_tests", 0)))}
            {_badge("通过", str(overall.get("total_passed", 0)))}
            {_badge("失败", str(overall.get("total_failed", 0)), overall.get("total_failed", 0) == 0)}
            {_badge("总耗时", f"{overall.get('elapsed_sec', 0):.2f}s")}
            {_badge("综合通过率", f"{overall.get('overall_pass_rate', 0)*100:.1f}%", overall.get("overall_pass_rate", 0) >= 0.95)}
        </div>
        """

        sections = ""

        # 耗时评估
        if timer_rows:
            sections += _card("⏱ 耗时评估", _table(
                ["模块", "调用次数", "平均(s)", "最小(s)", "最大(s)", "P95(s)", "P99(s)"],
                timer_rows
            ), "#9b59b6")

        # 性能指标
        if metrics_gauges:
            sections += _card("📊 性能指标", metrics_html, "#3498db")

        # 准确率
        if accuracy_rows:
            acc_total = accuracy.get("total", 0)
            acc_passed = accuracy.get("passed", 0)
            acc_rate = accuracy.get("pass_rate", 0)
            sections += _card("✅ 准确率评估",
                f"<p>{_badge('通过数', f'{acc_passed}/{acc_total}', acc_rate >= 0.95)}</p>" +
                _table(["模块", "总数", "通过", "通过率"], accuracy_rows),
            "#27ae60")

        # 鲁棒性
        if robust_rows:
            rob_total = robustness.get("total", 0)
            rob_passed = robustness.get("passed", 0)
            rob_rate = robustness.get("pass_rate", 0)
            sections += _card("🛡 鲁棒性评估",
                f"<p>{_badge('通过数', f'{rob_passed}/{rob_total}', rob_rate >= 0.95)}</p>" +
                _table(["模块", "总数", "通过", "通过率"], robust_rows),
            "#e67e22")

        # 完整性
        if complete_rows:
            comp_total = completeness.get("total", 0)
            comp_passed = completeness.get("passed", 0)
            comp_rate = completeness.get("pass_rate", 0)
            sections += _card("📦 完整性评估",
                f"<p>{_badge('通过数', f'{comp_passed}/{comp_total}', comp_rate >= 0.95)}</p>" +
                _table(["模块", "总数", "通过", "通过率"], complete_rows),
            "#1abc9c")

        return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>评估报告 - {timestamp}</title>
<style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background:#f5f6f8; margin:0; padding:20px; color:#333; }}
    .container {{ max-width:1200px; margin:0 auto; }}
    h1 {{ font-size:24px; margin-bottom:8px; }}
    .meta {{ color:#888; font-size:13px; margin-bottom:20px; }}
</style>
</head>
<body>
<div class="container">
    <h1>🧪 项目评估报告</h1>
    <div class="meta">生成时间: {timestamp} | 项目: 小动物夜谈会 / CodeX 生成代码评估</div>
    {_card("📋 总体概览", overall_content, "#2c3e50")}
    {sections}
</div>
</body>
</html>
"""
