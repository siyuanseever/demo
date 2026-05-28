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

## 6. 查看后台日志

另开一个终端：

```bash
tail -f logs/app.log
```

如果页面卡住，优先看最近几行是否停在：

- `deepseek request start`：模型 API 还没返回。
- `deepseek timeout`：模型请求超时。
- `http error`：后端接口报错。
- `reply done`：后端已生成回复，问题可能在前端展示。

当前默认 DeepSeek API 超时是 90 秒，Web 前端等待超时是 20 秒。调试时建议把 DeepSeek API 超时也改短：

```bash
DEEPSEEK_TIMEOUT=15
DEEPSEEK_THINKING=disabled
DEEPSEEK_STREAM=true
WEB_TIMEOUT_MS=20000
```

如果 fake 模式正常、真实模式停在 `deepseek request start` 后超时，说明问题在 DeepSeek API 响应速度、网络路径、额度/限流或模型服务侧，而不是本地前后端。

## 7. 不调用模型的测试模式

如果只想确认 Web UI、后端和 SQLite 链路是否正常：

```bash
LLM_PROVIDER=fake python3 -m app.web
```

fake 模式不会调用 DeepSeek，会立即返回测试回复。

## 8. DeepSeek 最小连通性测试

如果真实模型超时，先绕过 Web UI 和小鹿 prompt：

```bash
python3 -m app.ping_deepseek
```

这个命令只向 DeepSeek 发送一句 `pong` 测试。如果这里也超时，问题不在 Web UI，而在 DeepSeek API、网络、额度、模型服务或 key 配置。
