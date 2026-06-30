# Repository Guidelines — Harness Engineering Document

## 1. 项目定位与边界

This repository is a Python stdlib demo for **小动物夜谈会**, a psychological companion chat app.

- 核心目标：帮用户整理情绪、身体感受、内在冲突和关系模式，形成稳定、温和、可追溯的长期记忆。
- 非目标：不做诊断，不替代心理咨询、精神科治疗或危机干预。
- 第一版范围：本地 Web demo，核心是"对话体验 + 心理记忆 + 会后总结"。

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
- `docs/`, `TODO.md`, and `ROADMAP.md` document product direction and implementation notes.
- Runtime files live in `data/app.db` and `logs/app.log`; avoid committing private data.

---

## 3. Harness 工具链

所有可用的工程工具及其用途：

| 工具 | 命令 | 用途 |
|------|------|------|
| 语法校验 | `python3 -m compileall app` | Python 语法检查（Gate 0） |
| JS 校验 | `node --check /private/tmp/xiaolu-web-check.js` | 提取 web.py 中 JS 后的语法检查 |
| 综合评估 | `python3 -m app.evaluation.runner` | 五维度一键评估（Gate 1） |
| 自动诊断 | `python3 -m app.evaluation.diagnose` | 失败项自动分类（产品缺陷/测试缺陷） |
| Prompt 追踪 | Web UI `/prompt-inspector` | 实时查看 LLM 调用详情、token 用量、质量评分 |
| 体验评估 | `python3 -m app.evaluation.manual_eval` | 基于 cases 的手工/半自动评估 |

### 快速验证组合

每次变更后，根据变更类型选择对应的验证命令：

```bash
# Python 代码变更
python3 -m compileall app && python3 -m app.evaluation.runner

# web.py 变更（含 JS）
python3 -m compileall app && node --check /private/tmp/xiaolu-web-check.js && python3 -m app.evaluation.runner

# Prompt 文件变更
python3 -m compileall app && python3 -m app.evaluation.manual_eval

# 新增/删除模块
python3 -m compileall app && python3 -m app.evaluation.runner
```

---

## 4. 验证门控

门控是机器可验证的质量阈值，写入文档即成为工程契约。

### Gate 0：语法门控

- `python3 -m compileall app` 全部通过，无任何 SyntaxError。

### Gate 1：功能门控

- `python3 -m app.evaluation.runner` 综合通过率 >= 95%。
- 当前基线：90 个测试中通过 90 个，综合通过率 100%。

### Gate 2：结构门控

- `evaluation.completeness` 100% 通过。
- 关键文件、模块导入、AST 定义、依赖完整性全部检查通过。

### Gate 3：Prompt 门控

- Prompt JSON 有效率达到设定阈值（由 `prompt_evaluator` 自动评估）。
- 在 `/prompt-inspector` 页面实时查看。

### Gate 4：体验门控

- `python3 -m app.evaluation.manual_eval` 无高风险失败项。
- 心理陪伴产品的"被理解感"需通过 case-based 评估验证。

---

## 5. 编排规则

### 5.1 变更类型与触发门控映射

| 变更类型 | 触发门控 |
|---------|---------|
| Python 代码变更 | Gate 0 + Gate 1 |
| `app/web.py` 变更 | Gate 0 + JS 校验 + Gate 1 |
| Prompt 文件变更 | Gate 3 + Gate 4（手工 case 验证） |
| 新增/删除模块 | Gate 0 + Gate 1 + Gate 2 |
| Evaluation 框架变更 | Gate 0 + Gate 1 + Gate 2 |

### 5.2 失败响应流程

```
门控失败
  → 自动运行 python3 -m app.evaluation.diagnose
    → 产品代码缺陷 → 修复源代码 → 重跑门控
    → 测试代码缺陷 → 修复测试 → 重跑门控
    → 待人工确认 → 人工判断 → 修复对应方 → 重跑门控
```

### 5.3 Maker-Checker 工作流（所有 Agent 必须遵循）

本节定义了 Codex、Claude Code、TRAE 等所有 AI Agent 在本项目中修改代码时的**强制性工作流程**。

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
- Gate 1（runner）通过率必须 >= 95%
- 若有 JS 变更，还需运行 `node --check`

#### 第 4 步：分析测试结果

- 若全部通过 → 进入第 6 步
- 若有失败项 → 运行 `python3 -m app.evaluation.diagnose` 自动诊断

#### 第 5 步：诊断与修复

diagnose 工具将失败项自动分类为三类：

| 分类 | 含义 | 处理方式 |
|------|------|---------|
| **产品代码缺陷** | 源代码有问题 | Agent 可直接修复（若确定修改方案） |
| **测试代码缺陷** | 测试用例本身有问题 | 需与用户确认后再修改测试 |
| **待人工确认** | 无法自动判断 | 必须询问用户，不可自行修改 |

**确定可修改的情况**（Agent 可直接修复）：
- diagnose 明确指出修改位置和修改内容
- 修复方案简单、风险低（如添加关键词、添加 try-except）
- 不涉及产品逻辑变更

**不确定的情况**（必须先询问用户）：
- 修改可能影响产品行为或用户体验
- 修复方案有多种选择
- 涉及安全模块的策略调整
- 调用方是否需要同步修改不确定

修复后必须回到第 3 步重新运行测试，直到全部通过。

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
                                                    ├─ 产品缺陷 → 确定可修？→ 直接修复 → 重跑测试
                                                    │                          └─ 不确定 → 询问用户
                                                    ├─ 测试缺陷 → 询问用户
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
- `node --check /private/tmp/xiaolu-web-check.js` —— JS 语法校验

### 7.2 单元/集成测试层

- `python3 -m app.evaluation.runner` —— 五维度综合评估（耗时、性能、准确率、鲁棒性、完整性）
- 涵盖模块：`memory.store`、`characters`、`safety`、`knowledge`、`llm.base`、`orchestrator`

### 7.3 框架自测层

- `app/evaluation/tests/test_completeness.py` —— 完整性检查器自测
- `app/evaluation/tests/test_prompt_eval.py` —— Prompt 评估器自测
- `app/evaluation/tests/test_runner_integration.py` —— Runner 端到端集成测试

### 7.4 手工体验评估层

- `python3 -m app.evaluation.manual_eval` —— 基于 cases.yaml 的半自动评估
- 输出结构化报告到 `eval_reports/manual_eval_{timestamp}.json`

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
