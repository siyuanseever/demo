# 小鹿 · 心理陪伴 Agent

一个本地运行的自我理解型心理陪伴 Agent demo。小鹿不是心理治疗师，但可以帮你整理情绪、看见模式、获得稳定的长期记忆。

***

## ✨ 特性

- 🎯 **记忆系统**：8 大类结构化记忆，支持合并、更新和版本管理
- 📚 **知识卡**：内置心理学视角（依恋、IFS、CBT、ACT、创伤知情等）
- 📝 **会话总结**：每次结束自动生成 journal + 关键记忆
- 📊 **数据看板**：查看 sessions、messages、memories、journals
- 📈 **心情分析**：基于 journal 生成心情轨迹和日历视图
- 🔒 **本地存储**：所有数据存在本地 SQLite，不上云端

***

## 🖼️ 截图

### 对话界面
![对话界面](docs/screenshots/Chat.png)

### 数据看板 - 记忆视图
![记忆看板](docs/screenshots/Memory.png)

### 数据看板 - 知识卡视图
![知识卡看板](docs/screenshots/Knowledge.png)

### 数据看板 - 心情视图
![心情看板](docs/screenshots/Mood.png)

***

## 🚀 快速开始

### 1. 配置 API Key

复制环境变量模板：

```bash
cp .env.example .env
```

然后编辑 `.env`，填入你的 DeepSeek API Key：

```env
DEEPSEEK_API_KEY=sk-你的key
```

### 2. 启动 Web UI（推荐）

```bash
python3 -m app.web
```

然后在浏览器打开：

```text
http://127.0.0.1:8765
```

如果要在同一个 Wi‑Fi 下用手机访问，把 `.env` 改成：

```env
WEB_HOST=0.0.0.0
WEB_PORT=8765
```

重新启动后，终端会打印局域网访问地址。手机和 Mac 连同一个 Wi‑Fi，在手机浏览器打开这个地址即可。

### 3. 或者使用 CLI

```bash
python3 -m app.main
```

***

## 💡 使用方式

- **直接输入**：开始和小鹿对话
- **选择角色**：顶部可以切换绵绵羊、石石龟、墨墨鸦、忧忧兔、闪闪蝶、敢敢虎；角色设定在 `app/characters.py`
- **群聊自动**：开启后会根据你的输入自动选择更合适的小动物回复；当前是规则版选角，不额外消耗模型调用
- **结束会话**：点击「结束并总结」或输入 `/end`，会生成 journal 和最多 3 条长期记忆
- **数据看板**：顶部切换到「数据看板」查看所有保存的内容
  - `Sessions`：会话列表
  - `Memories`：按类别分组的记忆
  - `Knowledge`：小鹿可参考的知识卡
  - `Mood`：心情轨迹和周报原型
  - `Journals`：会话总结
  - `Messages`：所有消息

***

## 🗒️ 开发清单

- 长期规划见 `ROADMAP.md`
- 近期开发 TODO 见 `TODO.md`

***

## 🛠️ 调试模式

### 不调用模型的测试模式

```bash
LLM_PROVIDER=fake python3 -m app.web
```

### DeepSeek 连通性测试

```bash
python3 -m app.ping_deepseek
```

### 查看后台日志

```bash
tail -f logs/app.log
```

***

## 📁 项目结构

```
demo/
├── app/
│   ├── agents/          # 编排、安全检查
│   ├── evals/           # 评估标准、测试用例
│   ├── knowledge/       # 心理学知识卡
│   ├── llm/             # LLM 客户端
│   ├── memory/          # 记忆存储和检索
│   ├── prompts/         # 所有 Prompt 模板
│   ├── main.py          # CLI 入口
│   └── web.py           # Web UI 入口
├── data/
│   └── app.db           # SQLite 数据库
├── logs/
│   └── app.log          # 运行日志
├── docs/                # 产品文档
├── ROADMAP.md           # 长期规划
└── README.md            # 本文件
```

***

## 🎯 产品原则

1. 第一目标是帮助用户获得自我理解，不是替代治疗
2. 所有功能都要服务「被理解感、准确度、边界感、长期记忆质量」
3. 先做深，不做多
4. 不用功能数量证明价值
5. 每次迭代都要能被体验和评分

***

## ⚠️ 重要提醒

小鹿不是心理治疗师，也不是危机干预工具。如果出现现实危险，请优先联系现实支持或专业人士。

***

## 📄 许可证

本项目采用**双重许可**策略，区分代码和创意素材：

### 💻 代码部分（MIT License）

所有 Python 代码、HTML/CSS/JavaScript、配置文件等技术代码，采用 **MIT 许可证**开放。你可以自由使用、修改和分发，用于个人或商业项目。

### 🎨 素材部分（CC BY-NC-SA 4.0）

以下创意素材采用 **CC BY-NC-SA 4.0** 许可证，**保留所有商业权利**：

- 🐑🐢🐦‍⬛🐰🦋🐯 所有角色设计、角色设定和角色文案
- 🖼️ `app/static/` 下的所有图片素材（头像、背景、展示图等）
- ✨ 世界观描述、产品文案和心理知识卡片内容

**素材使用说明：**
- ✅ 可以学习、参考
- ✅ 个人非商业使用可以保留
- ❌ 未经许可不得用于商业用途
- ❌ 不得将角色设计用于其他产品

---

简单来说：代码随便用，可爱的小动物们要保护好～
