# 运行手册

## 1. 配置 API Key

不要把 API key 写进代码。推荐新建 `.env`：

```bash
cp .env.example .env
```

然后把 `.env` 里的 `DEEPSEEK_API_KEY` 改成你的 key。

也可以只在当前 shell 里设置：

```bash
export DEEPSEEK_API_KEY="你的 key"
```

## 2. 启动 Web UI

推荐先用浏览器界面，用户和小鹿更容易区分：

```bash
python3 -m app.web
```

然后打开：

```text
http://127.0.0.1:8765
```

## 3. 启动 CLI

```bash
python3 -m app.main
```

## 4. 使用方式

- 直接输入内容开始对话。
- 输入 `/end` 结束会话，并生成 journal 与最多 3 条长期记忆。
- 输入 `/quit` 直接退出，不生成总结。

## 5. 数据位置

默认数据库在：

```text
data/app.db
```
