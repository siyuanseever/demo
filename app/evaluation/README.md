# 项目评估体系 (Evaluation Framework)

为 CodeX 生成的代码提供多维度、可量化、可扩展的评估能力。

---

## 目录

- [快速开始](#快速开始)
- [五大评估维度详解](#五大评估维度详解)
  - [1. 耗时评估](#1-耗时评估)
  - [2. 性能评估](#2-性能评估)
  - [3. 准确率评估](#3-准确率评估)
  - [4. 鲁棒性评估](#4-鲁棒性评估)
  - [5. 完整性评估](#5-完整性评估)
- [评估结果解读](#评估结果解读)
- [失败项处理指南](#失败项处理指南)
- [如何扩展新模块评估](#如何扩展新模块评估)
- [项目文件说明](#项目文件说明)

---

## 快速开始

### 一键运行全部评估

```bash
python3 -m app.evaluation.runner
```

可选参数：

```bash
python3 -m app.evaluation.runner --project-root . --output-dir ./reports
```

### 前端可视化页面（推荐）

启动 Web 服务后，在浏览器打开：

```
http://localhost:8768/prompt-inspector
```

页面包含两个标签页：
- **Prompt 追踪** —— 实时查看每次 LLM 调用的完整 prompt 内容、响应、token 用量、耗时
- **代码评估** —— 可视化展示现有评估结果（耗时、准确率、鲁棒性、完整性）

支持的功能：
- 点击调用历史行 → 弹窗查看完整 prompt 拼接文本和 LLM 响应
- 实时质量评分（JSON 有效性、回复长度、响应时间等）
- 与现有评估报告联动，无需命令行即可查看全部数据

### 自动诊断失败项（推荐）

如果你看到"有测试未通过"，运行自动诊断工具，它会逐个分析失败项，并告诉你：**这是产品代码 bug，还是测试代码写错了**。

```bash
python3 -m app.evaluation.diagnose
```

输出示例：

```
======================================================================
🔍 评估失败项自动诊断报告
======================================================================

🐛 产品代码缺陷 (4 项) —— 需要修复源代码

  [1] 测试名称: crisis_detect_我想结束自己的生命
      所属模块: agents.safety
      失败原因: `detect_crisis()` 对输入返回了 False，但预期应为 True。
               说明 `CRISIS_KEYWORDS` 缺少该表达。
      修复建议: 在 `app/agents/safety.py` 的 `CRISIS_KEYWORDS` 中添加对应关键词。

💬 给 agent 的指令模板:
   "在 `app/agents/safety.py` 的 `CRISIS_KEYWORDS` 中添加对应关键词。"

📊 诊断汇总
   产品代码缺陷: 4 项 → 修复源代码
   测试代码缺陷: 0 项 → 修复测试用例
   待人工确认:   0 项 → 人工判断
```

### 查看原始报告

运行结束后会在 `eval_reports/` 目录生成两个文件：

- `eval_report_{timestamp}.json` —— 原始数据，包含每个测试的详细结果
- `eval_report_{timestamp}.html` —— 可视化报告，可直接在浏览器打开

### 输出示例

```
============================================================
📊 评估结果汇总
============================================================
   总测试数: 88
   通过: 84 | 失败: 4
   综合通过率: 95.5%
   总耗时: 0.17s

📁 报告已生成:
   JSON: eval_reports/eval_report_xxxx.json
   HTML: eval_reports/eval_report_xxxx.html
============================================================
```

---

## 五大评估维度详解

### 1. 耗时评估

**目标**：精确测量各模块函数调用的耗时分布。

**工作原理**：
- 使用 `Timer` 单例对象记录每次调用的耗时（秒）
- 支持两种模式：
  - **装饰器模式**：`@timed_decorator("label") def func(): ...`
  - **上下文管理器模式**：`with timed("label"): ...`
- 统计指标：调用次数、总耗时、最小值、最大值、平均值、P50、P95、P99

**具体执行方式**：

`tests/benchmarks.py` 中针对每个核心模块编写了基准测试函数：

| 模块 | 测试内容 | 调用次数 |
|---|---|---|
| `memory.store` | create_session / add_message / get_session_messages / list_sessions / search_memories | 约 70 次 |
| `knowledge.retriever` | retrieve 各种查询（正常/空/超长） | 6 次 |
| `characters` | get_character / auto_select_character | 11 次 |
| `safety` | detect_crisis 各种文本 | 6 次 |
| `llm.base` | LLMResponse 对象创建 | 50 次 |
| `orchestrator` | parse_json_object / render_memories / render_state_profiles | 约 60 次 |

**重要说明**：耗时评估是**纯本地测试**，不涉及任何外部 API 调用。所有测试在临时目录和内存中运行，不会产生网络请求。

**在业务代码中使用**：

```python
from app.evaluation.timer import timed, timed_decorator

# 方式1: 上下文管理器
with timed("my_module.heavy_operation"):
    result = heavy_operation()

# 方式2: 装饰器
@timed_decorator("my_module.api_call")
def api_call():
    return requests.get(...)
```

---

### 2. 性能评估

**目标**：采集进程级资源使用指标。

**工作原理**：
- 依赖 `psutil` 库读取进程内存（RSS/VMS）和 CPU 使用率
- 支持计数器（counter）、仪表盘（gauge）、直方图（histogram）三种指标类型

**为什么当前性能指标全为 0？**

首次运行环境中未安装 `psutil` 库，框架自动降级，内存和 CPU 采集返回 0。这不影响其他维度的评估。

**解决方案**：

```bash
pip install psutil
```

安装后重新运行，即可看到真实的内存和 CPU 数据。

**指标类型说明**：

| 类型 | 方法 | 用途 |
|---|---|---|
| Counter | `increment(name, value)` | 计数，如请求次数 |
| Gauge | `gauge(name, value)` | 瞬时值，如内存用量 |
| Histogram | `record(name, value)` | 分布统计，如响应时间 |

---

### 3. 准确率评估

**目标**：验证模块功能输出是否符合预期。

**工作原理**：
- 为每个模块编写 `AccuracyTest` 子类
- 在 `run()` 方法中调用被测函数，使用断言方法对比预期与实际
- 支持的断言类型：
  - `assert_equal()` —— 严格相等
  - `assert_contains()` —— 包含关系
  - `assert_true()` —— 布尔条件
  - `assert_custom()` —— 自定义验证函数

**准确率计算公式**：

```
通过率 = 通过的断言数 / 总断言数 × 100%
```

**当前覆盖的模块**：

| 模块 | 测试内容 |
|---|---|
| `memory.store` | Session 创建/查询/消息添加/列表/搜索 |
| `characters` | 角色获取、自动选择 |
| `safety` | 危机文本检测（应检出） vs 安全文本（不应检出） |
| `knowledge` | 检索返回格式、空查询处理 |
| `llm.base` | 数据结构创建 |
| `orchestrator` | JSON 解析、模板渲染 |

**当前结果**：40 个断言中通过 38 个，通过率 95%。

---

### 4. 鲁棒性评估

**目标**：测试系统在异常输入、边界条件、并发场景下的稳定性。

**工作原理**：
- 为每个模块编写 `RobustnessTest` 子类
- 三种测试场景：
  - `test_edge_case()` —— 边界条件测试（空输入、超长输入、特殊字符）
  - `test_concurrent()` —— 并发测试（多线程同时调用）
  - `test_stress()` —— 压力测试（连续高频调用）

**通过标准**：

| 场景 | 通过条件 |
|---|---|
| 边界条件 | 函数不抛出未预期异常，正常返回或按预期抛出特定异常 |
| 并发 | 所有并发调用均成功完成，无死锁、无竞争 |
| 压力 | 连续调用中无异常崩溃，性能可接受 |

**当前覆盖的模块**：

| 模块 | 测试场景 |
|---|---|
| `memory.store` | 空 session_id、超长消息、特殊字符、并发创建 session、连续添加消息 |
| `characters` | None/空字符串、超长文本、并发获取角色 |
| `safety` | 空输入、超长输入、连续检测 200 次 |
| `knowledge` | 空查询、超长查询、特殊字符、并发检索 |
| `orchestrator` | 无效 JSON、空字符串、异常格式数据 |

**当前结果**：29 个测试中通过 27 个，通过率 93.1%。

---

### 5. 完整性评估

**目标**：检查代码结构是否完整、模块是否可导入、依赖是否齐全。

**工作原理**：
- `CompletenessChecker` 执行四类检查：

| 检查类型 | 说明 |
|---|---|
| `file_exists` | 关键文件是否存在 |
| `importable` | 模块是否可以正常导入 |
| `class_methods` | 类是否包含预期的方法 |
| `ast_definitions` | 通过 AST 静态分析检查函数/类定义 |
| `dependencies` | 依赖的第三方/标准库是否可导入 |

**当前检查项**：

- 10 个关键文件存在性检查
- 4 个模块可导入性检查
- 3 个 AST 定义检查（DeepSeekClient、Store、ConversationOrchestrator）
- 2 个依赖完整性检查

**当前结果**：19 项全部通过，通过率 100%。

---

## 评估结果解读

### 最新运行结果（修复后）

```
总测试数: 88
通过: 84 | 失败: 4
综合通过率: 95.5%
```

| 维度 | 测试数 | 通过 | 失败 | 通过率 |
|---|---|---|---|---|
| 耗时评估 | 51 个数据点 | 全部记录 | — | — |
| 性能指标 | 3 项指标 | 已采集 | — | — |
| 准确率 | 40 个断言 | 38 | 2 | 95.0% |
| 鲁棒性 | 29 个场景 | 27 | 2 | 93.1% |
| 完整性 | 19 项检查 | 19 | 0 | 100% |

### 失败项详情

**失败 1-2：safety 准确率 —— 危机检测遗漏**

- 测试输入：`"我想结束自己的生命"`、`"结束这一切"`
- 实际结果：`detect_crisis()` 返回 `False`
- 预期结果：应返回 `True`
- 根因：`safety.py` 的 `CRISIS_KEYWORDS` 未覆盖这两种表达
- 处理建议：补充关键词 `"结束自己的生命"`、`"结束这一切"` 到 `CRISIS_KEYWORDS`

**失败 3-4：orchestrator 鲁棒性 —— 无效 JSON 处理**

- 测试输入：`"not json"`、`""`
- 实际结果：`parse_json_object()` 抛出 `JSONDecodeError`
- 预期结果：应优雅处理，不抛异常
- 根因：`orchestrator.py` 未对 `json.loads()` 做 try-except 保护
- 处理建议：在 `parse_json_object()` 中添加异常捕获，返回 `None` 或空字典

---

## 失败项处理指南

### 何时需要修复？

| 失败类型 | 是否需要修复被测代码？ | 说明 |
|---|---|---|
| 功能缺陷（如 safety 漏检） | ✅ 是 | 被测代码存在真实 bug |
| 边界未处理（如 JSON 解析异常） | ✅ 是 | 被测代码鲁棒性不足 |
| 测试代码本身错误 | ✅ 修复测试 | 断言条件写错、参数传递错误 |
| 预期与实际不一致（设计变更） | ⚠️ 评估后决定 | 可能是需求变更导致 |

### 处理流程

```
1. 查看 HTML 报告或 JSON 报告定位失败项
2. 判断是被测代码问题还是测试代码问题
3. 修复被测代码 或 调整测试断言
4. 重新运行评估验证
5. 持续监控，设置通过率阈值（如 >= 95%）
```

### 设置质量门禁

可以在 CI/CD 或自动化流程中加入：

```python
from app.evaluation.runner import EvaluationRunner

runner = EvaluationRunner(".")
result = runner.run_all()

overall = result["overall"]
if overall["overall_pass_rate"] < 0.95:
    raise RuntimeError(f"评估未通过: 通过率 {overall['overall_pass_rate']*100:.1f}% < 95%")
```

---

## 如何扩展新模块评估

### 步骤 1：添加准确率测试

在 `tests/test_accuracy.py` 中添加：

```python
class MyModuleAccuracyTest(AccuracyTest):
    def __init__(self):
        super().__init__("my_module", "my_module.name")

    def run(self):
        from my_module import my_function

        # 严格相等
        self.assert_equal("basic_case", my_function(2), 4)

        # 包含关系
        self.assert_contains("has_keyword", my_function("hello"), "ell")

        # 布尔条件
        self.assert_true("returns_positive", my_function(5) > 0)

        # 自定义验证
        self.assert_custom("custom_check",
            lambda: my_function("x") is not None,
            expected_desc="返回非None",
        )

        return self.results
```

在 `get_accuracy_tests()` 中注册：

```python
def get_accuracy_tests():
    return [
        # ... 已有测试
        MyModuleAccuracyTest(),
    ]
```

### 步骤 2：添加鲁棒性测试

在 `tests/test_robustness.py` 中添加：

```python
class MyModuleRobustnessTest(RobustnessTest):
    def __init__(self):
        super().__init__("my_module", "my_module.name")

    def run(self):
        from my_module import my_function

        # 边界: 空输入
        self.test_edge_case("empty_input", my_function, "")

        # 边界: 超长输入
        self.test_edge_case("long_input", my_function, "x" * 100000)

        # 并发: 10 线程各调用 10 次
        self.test_concurrent("concurrent",
            my_function,
            [("arg1",), ("arg2",)] * 10,
            max_workers=10)

        # 压力: 连续调用 100 次
        self.test_stress("stress",
            my_function,
            iterations=100,
            args=("test",))

        return self.results
```

在 `get_robustness_tests()` 中注册。

### 步骤 3：添加耗时基准

在 `tests/benchmarks.py` 中添加：

```python
def benchmark_my_module() -> list[dict]:
    from my_module import my_function
    timer = Timer()

    for i in range(100):
        with timed("my_module.my_function", timer):
            my_function(i)

    return timer.summary()
```

在 `run_all_benchmarks()` 的列表中添加 `benchmark_my_module`。

### 步骤 4：添加完整性检查

在 `runner.py` 的 `_run_completeness_checks()` 中添加：

```python
checker.check_file_exists("app/my_module.py", "我的模块")
checker.check_module_importable("app.my_module")
checker.check_ast_definitions("app/my_module.py", expected_functions=["my_function"])
```

---

## 项目文件说明

```
app/evaluation/
├── __init__.py              # 包入口，导出核心类
├── README.md                # 本文档
├── timer.py                 # 耗时追踪（Timer, timed, timed_decorator）
├── metrics.py               # 性能指标采集（MetricsCollector）
├── accuracy.py              # 准确率测试框架（AccuracyTest, accuracy_suite）
├── robustness.py            # 鲁棒性测试框架（RobustnessTest, robustness_suite）
├── completeness.py          # 完整性检查（CompletenessChecker）
├── reporter.py              # 报告生成器（JSON + HTML）
├── runner.py                # 主运行器（一键运行全部评估）
├── diagnose.py              # 失败项自动诊断工具
├── prompt_tracker.py        # Prompt 调用追踪器（拦截 LLM 调用，记录完整 prompt）
├── prompt_evaluator.py      # Prompt 效果评估（质量评分、JSON 有效性、token 效率）
└── tests/
    ├── __init__.py
    ├── benchmarks.py        # 耗时基准测试用例
    ├── test_accuracy.py     # 准确率测试用例
    └── test_robustness.py   # 鲁棒性测试用例
```

**前端页面**（位于 `app/web.py` 中）：

| 路由 | 说明 |
|---|---|
| `/prompt-inspector` | Prompt 追踪与效果评估可视化页面 |
| `/api/prompt-calls` | 获取 Prompt 调用历史列表 |
| `/api/prompt-call-detail?id=xxx` | 获取单次调用详情 + 质量评分 |
| `/api/prompt-eval-summary` | 获取 Prompt 效果评估汇总 |
| `/api/eval-summary` | 获取代码评估汇总（JSON） |

---

## 常见问题

**Q: 耗时评估是否真的移除了 API 调用？**

是的。所有耗时基准测试都是纯本地操作：
- `memory.store` 使用临时 SQLite 数据库
- `characters` / `safety` / `orchestrator` 是纯函数计算
- `knowledge.retriever` 读取嵌入的静态列表
- `llm.base` 仅创建数据对象

没有任何 HTTP 请求或外部 API 调用。

**Q: 性能指标为什么全是 0？**

因为环境缺少 `psutil` 库。安装后即可获取真实内存/CPU数据：

```bash
pip install psutil
```

**Q: 如何单独运行某个维度的评估？**

可以导入具体模块运行：

```python
from app.evaluation.tests.test_accuracy import get_accuracy_tests
from app.evaluation.accuracy import accuracy_suite

result = accuracy_suite(get_accuracy_tests())
print(result["pass_rate"])
```

**Q: 评估耗时多久？**

当前全部评估约 0.2 秒完成，因为不涉及网络调用。若加入真实的 LLM API 调用评估，耗时会相应增加。
