# Repository Guidelines — Harness Engineering Document

## 1. 项目定位与边界

This repository contains the Python stdlib backend/Web demo and the SwiftUI Apple-platform app for **小动物夜谈会**, a psychological companion chat app.

- 核心目标：帮用户整理情绪、身体感受、内在冲突和关系模式，形成稳定、温和、可追溯的长期记忆。
- 非目标：不做诊断，不替代心理咨询、精神科治疗或危机干预。
- 当前开发主线：Mac 应用体验整合与稳定化，核心是“心流 ↔ 夜谈互融 + 性能鲁棒性 + 数据/UI 完整性”。
- Web/Python 当前作为数据、模型和兼容性基线维护，不主动扩展无关功能。

---

## 2. 项目结构

- `app/web.py` contains the local Web UI, HTTP routes, embedded CSS, and browser JavaScript.
- `app/agents/` contains orchestration and safety logic.
- `app/llm/` contains model adapters, including DeepSeek and the fake model.
- `app/memory/` contains SQLite schema and persistence code.
- `app/knowledge/` contains knowledge/content cards and retrieval helpers.
- `app/prompts/` contains prompts sent to the LLM.
- `app/evaluation/` contains the evaluation framework, test cases, and prompt quality assessment.
- `app/static/` stores avatars, cozy status images, and UI background assets.
- `ios/XiaodongwuYetanhui/` contains the SwiftUI app currently used for the Mac product direction.
- `docs/`, `TODO.md`, and `ROADMAP.md` document product direction and implementation notes.
- Runtime files live in `data/app.db` and `logs/app.log`; avoid committing private data.

---

## 3. Harness 工具链

所有可用的工程工具及其用途：

| 工具 | 命令 | 用途 |
|------|------|------|
| 语法校验 | `python3 -m compileall app` | Python 语法检查（Gate 0） |
| Web/SSE 校验 | `python3 -m app.evaluation.check_sse_stream` | 渲染并校验最新 JS，同时验证 SSE 契约 |
| 分层检查 | `python3 -m app.evaluation.check_harness` | Contract、UI、低成本质量检查 |
| 综合评估 | `python3 -m app.evaluation.runner` | 八个测试维度一键评估（Gate 1） |
| 自动诊断 | `python3 -m app.evaluation.diagnose` | 失败项自动分类（产品缺陷/测试缺陷） |
| Prompt 追踪 | Web UI `/prompt-inspector` | 实时查看 LLM 调用详情、token 用量、质量评分 |
| 体验评估 | `python3 -m app.evaluation.manual_eval` | 基于 cases 的手工/半自动评估 |
| Mac 构建 | Xcode 或目标 scheme 的 `xcodebuild` | Swift 编译、链接和目标平台验证 |
| Mac 性能 | Instruments / Time Profiler / 可复现场景计时 | 主线程停顿、数据库和视图刷新证据 |

### 快速验证组合

每次变更后，根据变更类型选择对应的验证命令：

```bash
# Python 代码变更
python3 -m compileall app && python3 -m app.evaluation.runner

# web.py 变更（含 JS）
python3 -m compileall app && python3 -m app.evaluation.check_sse_stream && python3 -m app.evaluation.runner

# Prompt 文件变更
python3 -m compileall app && python3 -m app.evaluation.runner && python3 -m app.evaluation.manual_eval

# 新增/删除模块
python3 -m compileall app && python3 -m app.evaluation.runner
```

---

## 4. 验证门控

门控是机器可验证的质量阈值，写入文档即成为工程契约。

### Gate 0：语法门控

- `python3 -m compileall app` 全部通过，无任何 SyntaxError。

### Gate 1：功能门控

- `python3 -m app.evaluation.runner` 必须以退出码 0 结束。
- 综合通过率必须 >= 95%。
- `accuracy`、`robustness`、`completeness`、`functional`、`api_resilience`、`framework` 六个关键维度必须 100%。
- 任一测试套件执行异常都视为失败，不允许以 0 项跳过。
- 最近记录基线：262 个检查中通过 262 个，综合通过率 100%（2026-07-02）。

### Gate M0：Mac 构建门控

- 所有 Swift/Mac 改动必须记录 scheme、destination、构建命令和退出码。
- 无 Xcode 或目标 Mac 能力时状态为 `blocked`，不得以 Python Gate 代替。

### Gate M1：Mac 体验与性能门控

- 功能变更必须验证加载、空状态、错误、点击、导航和返回。
- 性能变更必须提供可复现场景、数据规模和修改前后证据。
- 没有完成目标 Mac 人工或自动验证时记为 `pending_manual_validation`。

### Gate 2：结构门控

- `evaluation.completeness` 100% 通过。
- 关键文件、模块导入、AST 定义、依赖完整性全部检查通过。

### Gate 3：Prompt 审查

- 相关结构化调用的 Prompt JSON 有效率应 >= 95%。
- 在 `/prompt-inspector` 查看调用记录，并在汇报中记录样本范围和结果。
- 当前没有独立 CLI 门控；不得把“打开过页面”写成自动验证通过。

### Gate 4：体验审查

- `python3 -m app.evaluation.manual_eval` 只生成待评分表，不代表体验审查通过。
- 人工完成 case-based 评分后，必须确认所有用例已评分且无高风险失败项。
- 未完成人工评分时，Gate 4 状态必须记为 `pending`，不能记为通过。

---

## 5. 编排规则

### 5.1 变更类型与触发门控映射

| 变更类型 | 触发门控 |
|---------|---------|
| Python 代码变更 | Gate 0 + Gate 1 |
| `app/web.py` 变更 | Gate 0 + Web/SSE 校验 + Gate 1 |
| Prompt 文件变更 | Gate 3 + Gate 4（手工 case 验证） |
| 新增/删除模块 | Gate 0 + Gate 1 + Gate 2 |
| Evaluation 框架变更 | Gate 0 + Gate 1 + Gate 2 |
| Swift/Mac 功能变更 | Gate M0 + 对应交互场景 + 必要的后端 Gate |
| Swift/Mac 性能变更 | Gate M0 + Gate M1 + 必要的后端 Gate |

### 5.2 失败响应流程

```
门控失败
  → 自动运行 python3 -m app.evaluation.diagnose
    → 产品代码缺陷 → 修复源代码 → 重跑门控
    → 测试代码缺陷 → 修复测试 → 重跑门控
    → 待人工确认 → 人工判断 → 修复对应方 → 重跑门控
```

### 5.3 Checker / Fixer 角色隔离

自动化角色必须严格分工：

| 角色 | 可以修改 | 禁止修改 |
|------|---------|---------|
| Test / Checker Agent | `app/evaluation/**`、测试 fixture、测试报告 | 产品实现、Prompt、iOS 产品代码 |
| Product / Fixer / Executor Agent | 产品实现和必要产品文档 | `app/evaluation/**`、测试、fixture、case |
| Product Manager Agent | `status.md`、`TODO.md` 的授权区域和交接报告 | 产品代码、测试、`ROADMAP.md`、`plan.md`、自动化协议 |

- Checker 可以只读访问 `data/app.db` 生成私有评估或脱敏/合成测试，但不得持久化真实对话原文。
- Fixer 可以运行 Checker 提供的测试，但不得新增、删除、修改或放宽测试。
- Fixer 判断测试有问题时，只能生成结构化异议报告，由 Checker 复核。
- Checker 报告、Fixer 回执和复验结果使用 `docs/automation/` 中定义的通信协议。
- Checker 负责关闭 issue；Fixer 只能标记为 `fixed_pending_verification`。
- Checker 每 6 小时追加一份独立报告；Fixer 每天按 index + cursor 批量消费所有未处理报告，禁止只读取 `LATEST_CHECKER.json`。
- 双方使用持久分支 `automation/quality-loop` 串行提交，调度器负责互斥，不增加第三个智能 Agent。

完整 Prompt：

- `docs/automation/automation-orchestration.md`
- `docs/automation/checker-agent-prompt.md`
- `docs/automation/product-fixer-agent-prompt.md`
- `docs/automation/product-manager-agent-prompt.md`
- `docs/automation/executor-agent-prompt.md`

### 5.4 修改—检查工作流（所有 Agent 必须遵循）

本节定义所有 AI Agent 在各自权限内修改代码时的强制流程。

#### 第 1 步：修改前 — 读取上下文

- 读取 `AGENTS.md` 了解项目规范和门控标准
- 读取 `plan.md` 了解当前阶段目标
- 读取 `status.md` 了解当前进度和已知问题
- 读取待修改文件，理解现有代码逻辑

#### 第 2 步：修改代码

- 按需求修改代码，保持现有代码风格（4空格、snake_case）
- 每次修改尽量小，一个 commit 只做一件事
- 涉及安全相关修改（如 `safety.py`）需格外谨慎

#### 第 3 步：修改后 — 自动运行测试（必须）

```bash
# 每次代码变更后，必须运行以下命令验证：
python3 -m compileall app && python3 -m app.evaluation.runner
```

- Gate 0（compileall）必须零错误
- Gate 1（runner）必须退出码为 0，并满足关键维度 100%
- 若有 Web/JS 变更，还需运行 `python3 -m app.evaluation.check_sse_stream`

#### 第 4 步：分析测试结果

- 若 Gate 命令退出码为 0 且报告 `overall.gate_passed=true` → 进入第 6 步
- 若命令非零或报告有失败项 → 运行 `python3 -m app.evaluation.diagnose`

#### 第 5 步：诊断与修复

diagnose 工具将失败项自动分类为三类：

| 分类 | 含义 | 处理方式 |
|------|------|---------|
| **产品代码缺陷** | 源代码有问题 | 仅 Product / Fixer Agent 可修复 |
| **测试代码缺陷** | 测试用例本身有问题 | 仅 Test / Checker Agent 可修复 |
| **待人工确认** | 无法自动判断 | 必须询问用户，不可自行修改 |

**确定可修改的情况**（对应角色可直接修复）：
- Product / Fixer：Checker 测试能稳定复现、产品契约明确且不涉及安全策略选择。
- Test / Checker：能够证明断言、fixture 或 Harness 与已确认契约不一致。
- 修改范围属于当前角色的允许路径。

**不确定的情况**（必须先询问用户）：
- 修改可能影响产品行为或用户体验
- 修复方案有多种选择
- 涉及安全模块的策略调整
- 调用方是否需要同步修改不确定

修复后必须回到第 3 步重新运行测试。不能用总体通过率掩盖关键维度失败。

#### 第 6 步：汇报结果

向用户说明：
- 修改了什么文件、改了什么内容
- 测试结果（通过率、失败项）
- 修复了什么问题、如何修复的
- 若有不确定的部分，说明风险和建议

#### 完整流程图

```
读取上下文 → 修改代码 → 运行测试 → 分析结果
                                        ├─ 全通过 → 汇报结果
                                        └─ 有失败 → 运行 diagnose
                                                    ├─ 产品缺陷 → Fixer 确定可修？→ 修产品 → 重跑测试
                                                    │                          └─ 不确定 → 询问用户
                                                    ├─ 测试缺陷 → Checker 修测试 → 重跑测试
                                                    └─ 待确认   → 询问用户
```

---

## 6. 代码风格与命名约定

Use Python 3.12-compatible code and keep changes small. Prefer clear functions, explicit names, and simple control flow. Follow existing style: 4-space indentation, snake_case for Python names, and descriptive JSON keys. Keep UI changes in `app/web.py` unless a broader frontend split is intentional.

For character assets, use stable lowercase hyphenated filenames, for example `mianmian-sheep-cozy.webp`.

---

## 7. 测试体系

本项目采用分层测试策略：

### 7.1 快速验证层

- `python3 -m compileall app` —— Python 语法校验
- `python3 -m app.evaluation.check_sse_stream` —— 最新渲染 JS 与 SSE 契约校验

### 7.2 单元/集成测试层

- `python3 -m app.evaluation.runner` —— 八维度综合评估（准确率、鲁棒性、完整性、回复速度、回复质量、功能、API 鲁棒性、框架自测）
- 涵盖模块：`memory.store`、`characters`、`safety`、`knowledge`、`llm.base`、`orchestrator`

### 7.3 框架自测层

- `app/evaluation/tests/test_completeness.py` —— 完整性检查器自测
- `app/evaluation/tests/test_prompt_eval.py` —— Prompt 评估器自测
- `app/evaluation/tests/test_runner_integration.py` —— Runner 端到端集成测试

### 7.4 手工体验评估层

- `python3 -m app.evaluation.manual_eval` —— 基于 cases.yaml 的半自动评估
- 输出待人工评分表到 `eval_reports/manual_eval_{timestamp}.json`
- 所有 case 的 `status` 为 `pending_manual_review` 时，不构成 Gate 4 通过证据

### 7.5 Prompt 质量评估层

- Web UI `/prompt-inspector` —— 实时追踪每次 LLM 调用、质量评分、JSON 有效性

### 手动检查清单

Manual checks should cover: starting a session, sending a message, ending/summarizing a session, viewing dashboard data, switching roles, and group-auto role selection.

---

## 8. Commit & Pull Request Guidelines

Recent history uses mixed conventional and Chinese commit messages, such as `feat(web): ...`, `style(control-panel): ...`, and `docs(prompts): ...`. Prefer `type(scope): summary` when possible.

Pull requests should include: purpose, key files changed, validation commands run, screenshots for UI changes, and notes about any prompt, memory, or safety behavior changes.

---

## 9. 安全与配置

Keep API keys in `.env`; never hard-code or commit secrets. Use `.env.example` for new configuration names. Be careful with `data/app.db` and `logs/app.log`, because they may contain private conversation data.
