# AGENTS.md — 工程指南

## 1. 项目定位

**小动物夜谈会** — 一个 macOS 个人疗愈与成长陪伴应用。

- 核心功能：日常对话、情绪整理、生活记录、定时提醒
- 定位：个人使用的 Mac 应用，非商业产品
- 非目标：不做诊断，不替代心理咨询或危机干预
- 当前阶段：Mac Catalyst 稳定化，逐步向原生 macOS 迁移（见 ROADMAP.md N0-N5）
- 主要开发方式：Claude Code 作为 AI 编程助手，配合 Codex 使用

### 两个运行时

| 运行时 | 用途 | 状态 |
|--------|------|------|
| **SwiftUI Mac App** (`ios/`) | 主要产品界面，日常使用 | 主力开发 |
| **Python 后端** (`app/`) | Web UI、数据服务、LLM 编排 | 基线维护 |

Python 后端 `data/app.db` 是权威数据源；Mac App 沙盒数据库是缓存，通过网络 API 同步。

---

## 2. 项目结构

```
app/                          # Python 后端
├── web.py                    # Web UI (Quart/SSE) + 内嵌 HTML/CSS/JS
├── main.py                   # CLI 入口
├── agents/orchestrator.py    # 会话编排、对话逻辑
├── agents/safety.py          # 内容安全
├── llm/                      # LLM 适配器 (DeepSeek, Fake)
├── memory/store.py           # SQLite 记忆持久化
├── memory/schema.py          # 数据库 schema
├── knowledge/                # 心理学知识卡片
├── prompts/                  # LLM prompt 模板
├── characters.py             # 6 个陪伴角色定义
├── config.py                 # 环境配置
├── intent/                   # 意图识别
├── evaluation/               # 测试框架
└── static/                   # 头像、UI 素材

ios/XiaodongwuYetanhui/       # SwiftUI Mac App
├── App/                      # 应用入口
├── Views/                    # 界面 (MacPrototypeView 是主开发界面)
├── Services/                 # 服务层 (API、数据库、本地 LLM)
└── DerivedData-Mac/          # 构建产物 (gitignored)

docs/                          # 文档
├── automation/               # 事故处理 playbook
│   ├── mac-freeze-incident-playbook.md
│   └── mac-memory-incident-playbook.md
├── ROADMAP.md
├── TODO.md
├── plan.md
└── status.md
```

---

## 3. 常用命令

### Python 后端

```bash
# 启动 Web UI (http://127.0.0.1:8765)
python3 -m app.web

# CLI 模式
python3 -m app.main

# 无 LLM 测试模式
LLM_PROVIDER=fake python3 -m app.web

# DeepSeek 连通性测试
python3 -m app.ping_deepseek

# 查看日志
tail -f logs/app.log
```

### 验证命令

```bash
# 语法检查 (Gate 0)
python3 -m compileall app

# SSE/JS 契约检查
python3 -m app.evaluation.check_sse_stream

# 完整评估 (Gate 1) — 8 维度，需要 ≥95% 通过
python3 -m app.evaluation.runner

# 失败诊断
python3 -m app.evaluation.diagnose

# 手工体验评估 (Gate 4)
python3 -m app.evaluation.manual_eval
```

### 按变更类型选择验证

```bash
# Python 代码变更
python3 -m compileall app && python3 -m app.evaluation.runner

# web.py 变更 (含前端 JS)
python3 -m compileall app && python3 -m app.evaluation.check_sse_stream && python3 -m app.evaluation.runner

# Prompt 变更
python3 -m compileall app && python3 -m app.evaluation.runner && python3 -m app.evaluation.manual_eval
```

### Mac App 构建

```bash
# 脚本构建
./scripts/run_mac.sh

# 手动 xcodebuild
xcodebuild -project ios/XiaodongwuYetanhui.xcodeproj \
  -scheme XiaodongwuYetanhui \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath ios/DerivedData-Mac \
  CODE_SIGNING_ALLOWED=NO \
  build
```

---

## 4. 质量门控

门控是机器可验证的质量阈值。每次代码修改后，根据变更类型运行对应的门控检查。

### Gate 0：语法

- `python3 -m compileall app` 零错误

### Gate 1：功能

- `python3 -m app.evaluation.runner` 退出码为 0
- 综合通过率 ≥ 95%
- `accuracy`、`robustness`、`completeness`、`functional`、`api_resilience`、`framework` 六个关键维度 100%
- 任一测试套件执行异常视为失败

### Gate M0：Mac 构建

- `xcodebuild` 成功，记录 scheme、destination、构建命令和退出码
- 无 Xcode 环境时状态记为 `blocked`，不得以 Python Gate 代替

### Gate M1：Mac 体验与性能

- 功能变更：验证加载、空状态、错误、点击、导航
- 性能变更：提供可复现场景和数据规模的前后对比
- 发送卡死相关：执行 `docs/automation/mac-freeze-incident-playbook.md`
- 内存相关：执行 `docs/automation/mac-memory-incident-playbook.md`

### Gate 4：体验审查

- `python3 -m app.evaluation.manual_eval` 生成待评分表
- 需人工完成 case-based 评分，确认无高风险失败项
- 未完成人工评分时状态记为 `pending`

### 变更类型 → 门控映射

| 变更类型 | 需要通过的检查 |
|---------|--------------|
| Python 代码 | Gate 0 + Gate 1 |
| `app/web.py` | Gate 0 + SSE 检查 + Gate 1 |
| Prompt 文件 | Gate 1 + Gate 4 人工审查 |
| 新增/删除模块 | Gate 0 + Gate 1 |
| Swift/Mac 功能 | Gate M0 + 交互验证 |
| Swift/Mac 性能 | Gate M0 + Gate M1 |

### 门控失败处理

```
门控失败
  → 运行 python3 -m app.evaluation.diagnose 自动分类
    → 产品代码缺陷 → 修复源码 → 重跑门控
    → 测试代码缺陷 → 修复测试 → 重跑门控
    → 无法自动判断 → 人工确认后修复 → 重跑门控
```

---

## 5. 开发工作流

每次修改代码时遵循以下流程：

### 第 1 步：了解上下文

- 读取相关源码，理解现有逻辑
- 涉及架构决策时，先读 `plan.md` 和 `ROADMAP.md`

### 第 2 步：修改代码

- 保持现有代码风格（4 空格缩进、snake_case）
- 每次改动尽量小，一个 commit 做一件事
- 涉及 `safety.py` 或安全逻辑时格外谨慎

### 第 3 步：验证

- 根据变更类型运行对应的门控命令（见 §4 映射表）
- Gate 0 + Gate 1 是 Python 代码变更的最低要求

### 第 4 步：处理结果

- **全部通过** → 变更完成，汇报结果
- **有失败** → 运行 `diagnose` 分类，修复后回到第 3 步
- **不确定如何修** → 说明情况和风险，不要猜测，询问用户

```
了解上下文 → 修改代码 → 运行验证 → 全部通过 → 完成
                                    → 有失败 → diagnose → 修复 → 重跑验证
```

---

## 6. 代码风格

- Python 3.12+，4 空格缩进，snake_case
- 函数命名清晰，控制流简单直接
- JSON key 使用描述性命名
- 角色素材文件名：小写连字符，如 `mianmian-sheep-cozy.webp`
- UI 改动集中在 `app/web.py`，除非有意拆分前端

---

## 7. 测试体系

### 快速验证层

- `python3 -m compileall app` — 语法校验
- `python3 -m app.evaluation.check_sse_stream` — JS 渲染 + SSE 契约

### 综合评估层

- `python3 -m app.evaluation.runner` — 八维度评估（准确率、鲁棒性、完整性、回复速度、回复质量、功能、API 鲁棒性、框架自测）
- 涵盖模块：`memory.store`、`characters`、`safety`、`knowledge`、`llm.base`、`orchestrator`

### 手工体验层

- `python3 -m app.evaluation.manual_eval` — 基于 cases.yaml 的半自动评估
- Web UI `/prompt-inspector` — LLM 调用追踪、token 用量、质量评分

### 手动检查清单

覆盖：启动会话、发送消息、结束/总结会话、查看仪表盘、切换角色、group-auto 角色选择。

---

## 8. Commit 规范

- 格式：`type(scope): 描述`
- 常用 type：`feat`、`fix`、`refactor`、`perf`、`style`、`docs`、`chore`
- 中文或英文描述均可
- PR 应包含：改动目的、关键文件、验证命令及结果、UI 改动截图

---

## 9. 安全

- API Key 放在 `.env`（模板：`.env.example`），绝不提交
- `data/` 和 `logs/` 在 `.gitignore` 中（可能含私密对话数据）
- 不在代码或测试中硬编码真实对话内容
