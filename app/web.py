import json
import logging
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from app.config import get_settings
from app.main import build_orchestrator


HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>小鹿 · 心理陪伴 Agent</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f7f1e8;
      --panel: #fffaf3;
      --user: #d9ecff;
      --deer: #fff;
      --text: #2d2620;
      --muted: #806f60;
      --accent: #a66a3f;
      --border: #eadac8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: radial-gradient(circle at top, #fff7e9, var(--bg));
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .app {
      width: min(920px, 100vw);
      height: 100vh;
      margin: 0 auto;
      display: grid;
      grid-template-rows: auto 1fr auto;
      padding: 18px;
      gap: 14px;
    }
    header {
      background: rgba(255, 250, 243, 0.82);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 16px 18px;
      box-shadow: 0 10px 28px rgba(120, 80, 40, 0.08);
    }
    h1 { margin: 0; font-size: 22px; }
    .subtitle { margin-top: 6px; color: var(--muted); font-size: 14px; }
    #messages {
      overflow-y: auto;
      background: rgba(255, 250, 243, 0.64);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 18px;
    }
    .row { display: flex; margin: 12px 0; }
    .row.user { justify-content: flex-end; }
    .bubble {
      max-width: min(680px, 86%);
      padding: 12px 14px;
      border-radius: 18px;
      line-height: 1.65;
      white-space: pre-wrap;
      box-shadow: 0 4px 16px rgba(70, 45, 20, 0.06);
    }
    .user .bubble {
      background: var(--user);
      border-top-right-radius: 6px;
    }
    .deer .bubble {
      background: var(--deer);
      border: 1px solid var(--border);
      border-top-left-radius: 6px;
    }
    .name {
      font-size: 12px;
      color: var(--muted);
      margin-bottom: 4px;
    }
    form {
      display: grid;
      grid-template-columns: 1fr auto auto;
      gap: 10px;
      align-items: end;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 12px;
    }
    textarea {
      width: 100%;
      min-height: 52px;
      max-height: 160px;
      resize: vertical;
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 12px;
      font: inherit;
      background: white;
      color: var(--text);
    }
    button {
      border: 0;
      border-radius: 14px;
      padding: 12px 16px;
      font: inherit;
      cursor: pointer;
      background: var(--accent);
      color: white;
    }
    button.secondary {
      background: #e9dac9;
      color: #4b3829;
    }
    button:disabled { opacity: 0.55; cursor: not-allowed; }
    .system {
      text-align: center;
      color: var(--muted);
      font-size: 13px;
      margin: 12px 0;
      white-space: pre-wrap;
    }
  </style>
</head>
<body>
  <main class="app">
    <header>
      <h1>小鹿 · 心理陪伴 Agent</h1>
      <div class="subtitle">本地 demo。小鹿不是心理治疗师；如果出现现实危险，请优先联系现实支持。</div>
    </header>
    <section id="messages"></section>
    <form id="form">
      <textarea id="input" placeholder="把此刻想说的话写在这里。Shift+Enter 换行，Enter 发送。"></textarea>
      <button id="send" type="submit">发送</button>
      <button id="end" class="secondary" type="button">结束并总结</button>
    </form>
  </main>
  <script>
    const messages = document.querySelector("#messages");
    const input = document.querySelector("#input");
    const form = document.querySelector("#form");
    const send = document.querySelector("#send");
    const end = document.querySelector("#end");

    let sessionId = null;
    let busy = false;

    function setBusy(value) {
      busy = value;
      send.disabled = value;
      end.disabled = value;
      input.disabled = value;
      send.textContent = value ? "等待中..." : "发送";
    }

    function addMessage(role, text) {
      const row = document.createElement("div");
      row.className = "row " + (role === "user" ? "user" : "deer");
      const bubble = document.createElement("div");
      bubble.className = "bubble";
      const name = document.createElement("div");
      name.className = "name";
      name.textContent = role === "user" ? "你" : "小鹿";
      const body = document.createElement("div");
      body.textContent = text;
      bubble.appendChild(name);
      bubble.appendChild(body);
      row.appendChild(bubble);
      messages.appendChild(row);
      messages.scrollTop = messages.scrollHeight;
    }

    function addSystem(text) {
      const node = document.createElement("div");
      node.className = "system";
      node.textContent = text;
      messages.appendChild(node);
      messages.scrollTop = messages.scrollHeight;
    }

    const WEB_TIMEOUT_MS = __WEB_TIMEOUT_MS__;

    async function post(path, payload = {}, timeoutMs = WEB_TIMEOUT_MS) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      let response;
      try {
        response = await fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      } catch (error) {
        if (error.name === "AbortError") {
          throw new Error("请求超过 " + Math.round(timeoutMs / 1000) + " 秒未返回。请看 logs/app.log 判断是模型超时还是网络问题。");
        }
        throw error;
      } finally {
        clearTimeout(timer);
      }
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "请求失败");
      return data;
    }

    async function start() {
      const data = await post("/api/session");
      sessionId = data.session_id;
      addSystem("新的会话已开始。");
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (busy) return;
      const text = input.value.trim();
      if (!text) return;
      input.value = "";
      addMessage("user", text);
      addSystem("小鹿正在思考。如果超过 " + Math.round(WEB_TIMEOUT_MS / 1000) + " 秒，会自动解锁。");
      setBusy(true);
      try {
        const data = await post("/api/chat", { session_id: sessionId, text });
        addMessage("deer", data.reply);
      } catch (error) {
        addSystem(error.message);
      } finally {
        setBusy(false);
        input.focus();
      }
    });

    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        form.requestSubmit();
      }
    });

    end.addEventListener("click", async () => {
      if (busy) return;
      setBusy(true);
      try {
        const data = await post("/api/end", { session_id: sessionId });
        addSystem("会话总结：\\n" + data.journal.summary);
        if (data.memories.length) {
          addSystem("新增记忆：\\n" + data.memories.map(m => "- [" + m.category + "] " + m.content).join("\\n"));
        } else {
          addSystem("这次没有新增长期记忆。");
        }
        await start();
      } catch (error) {
        addSystem(error.message);
      } finally {
        setBusy(false);
        input.focus();
      }
    });

    start().catch(error => addSystem(error.message));
  </script>
</body>
</html>
"""


class WebApp:
    def __init__(self) -> None:
        self.orchestrator = build_orchestrator()


class Handler(BaseHTTPRequestHandler):
    app: WebApp
    logger = logging.getLogger(__name__)

    def do_GET(self) -> None:
        if urlparse(self.path).path != "/":
            self.send_error(404)
            return
        settings = get_settings()
        html = HTML.replace("__WEB_TIMEOUT_MS__", str(settings.web_timeout_ms))
        self.respond_html(html)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        started_at = time.monotonic()
        self.logger.info("http start path=%s", path)
        try:
            if path == "/api/session":
                session_id = self.app.orchestrator.start_session()
                self.respond_json({"session_id": session_id})
                return
            payload = self.read_json()
            if path == "/api/chat":
                reply = self.app.orchestrator.reply(payload["session_id"], payload["text"])
                self.respond_json({"reply": reply})
                return
            if path == "/api/end":
                result = self.app.orchestrator.close_session(payload["session_id"])
                self.respond_json(result)
                return
            self.send_error(404)
        except Exception as error:
            self.logger.exception("http error path=%s", path)
            self.respond_json({"error": str(error)}, status=500)
        finally:
            self.logger.info(
                "http done path=%s elapsed=%.2fs",
                path,
                time.monotonic() - started_at,
            )

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        return json.loads(body or "{}")

    def respond_html(self, html: str) -> None:
        data = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def respond_json(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    Handler.app = WebApp()
    server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
    print("小鹿 Web UI 已启动：http://127.0.0.1:8765")
    print("后台日志：logs/app.log")
    print("按 Ctrl+C 停止。")
    server.serve_forever()


if __name__ == "__main__":
    main()
