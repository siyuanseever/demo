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
      width: min(1120px, 100vw);
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
    nav {
      display: flex;
      gap: 10px;
      margin-top: 14px;
    }
    .tab {
      background: #eadac8;
      color: #4b3829;
      padding: 8px 12px;
      border-radius: 999px;
    }
    .tab.active {
      background: var(--accent);
      color: #fff;
    }
    .view { min-height: 0; overflow: hidden; }
    .hidden { display: none !important; }
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
    #dashboard {
      overflow-y: auto;
      background: rgba(255, 250, 243, 0.64);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 18px;
    }
    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-bottom: 14px;
    }
    .toolbar button {
      background: #e9dac9;
      color: #4b3829;
      padding: 9px 12px;
    }
    .toolbar button.active {
      background: var(--accent);
      color: #fff;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 12px;
    }
    .stack {
      display: grid;
      gap: 14px;
    }
    .group-title {
      margin: 10px 0 4px;
      font-size: 18px;
      color: #5f3d26;
    }
    .card {
      background: #fff;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 14px;
      box-shadow: 0 4px 16px rgba(70, 45, 20, 0.05);
    }
    .card h3 {
      margin: 0 0 8px;
      font-size: 16px;
    }
    .meta {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
      overflow-wrap: anywhere;
    }
    .content {
      margin-top: 10px;
      white-space: pre-wrap;
      line-height: 1.6;
    }
    .pill {
      display: inline-block;
      padding: 3px 8px;
      border-radius: 999px;
      background: #f2e5d6;
      color: #6f4a31;
      font-size: 12px;
      margin-right: 6px;
      margin-top: 6px;
    }
    .empty {
      color: var(--muted);
      text-align: center;
      padding: 42px 8px;
    }
  </style>
</head>
<body>
  <main class="app">
    <header>
      <h1>小鹿 · 心理陪伴 Agent</h1>
      <div class="subtitle">本地 demo。小鹿不是心理治疗师；如果出现现实危险，请优先联系现实支持。</div>
      <nav>
        <button id="chatTab" class="tab active" type="button">对话</button>
        <button id="dataTab" class="tab" type="button">数据看板</button>
      </nav>
    </header>
    <section id="messages" class="view"></section>
    <section id="dashboard" class="view hidden">
      <div class="toolbar">
        <button data-view="sessions" class="active" type="button">Sessions</button>
        <button data-view="memories" type="button">Memories</button>
        <button data-view="journals" type="button">Journals</button>
        <button data-view="messages" type="button">Messages</button>
        <button id="refreshData" type="button">刷新</button>
        <button id="cleanupSessions" type="button">清理空 Sessions</button>
      </div>
      <div id="dataList" class="grid"></div>
    </section>
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
    const chatTab = document.querySelector("#chatTab");
    const dataTab = document.querySelector("#dataTab");
    const dashboard = document.querySelector("#dashboard");
    const dataList = document.querySelector("#dataList");
    const refreshData = document.querySelector("#refreshData");
    const cleanupSessions = document.querySelector("#cleanupSessions");
    const dataButtons = [...document.querySelectorAll("[data-view]")];

    let sessionId = null;
    let busy = false;
    let activeDataView = "sessions";

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

    async function get(path) {
      const response = await fetch(path);
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
          addSystem("记忆处理：\\n" + data.memories.map(m => "- " + (m.action || "create") + " [" + m.category + "/" + (m.subcategory || "general") + "] " + m.content).join("\\n"));
        } else {
        addSystem("这次没有新增长期记忆。");
        }
        await loadData(activeDataView);
        await start();
      } catch (error) {
        addSystem(error.message);
      } finally {
        setBusy(false);
        input.focus();
      }
    });

    function switchMainView(view) {
      const showData = view === "data";
      dashboard.classList.toggle("hidden", !showData);
      messages.classList.toggle("hidden", showData);
      form.classList.toggle("hidden", showData);
      chatTab.classList.toggle("active", !showData);
      dataTab.classList.toggle("active", showData);
      if (showData) loadData(activeDataView);
    }

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");
    }

    function shortId(id) {
      return String(id || "").slice(0, 8);
    }

    function renderList(items, renderer) {
      if (!items.length) {
        dataList.className = "";
        dataList.innerHTML = '<div class="empty">还没有保存的数据。</div>';
        return;
      }
      dataList.className = "grid";
      dataList.innerHTML = items.map(renderer).join("");
    }

    function renderSessions(items) {
      renderList(items, item => `
        <article class="card">
          <h3>Session ${escapeHtml(shortId(item.id))}</h3>
          <div class="meta">id: ${escapeHtml(item.id)}</div>
          <div class="meta">created: ${escapeHtml(item.created_at)}</div>
          <div class="meta">ended: ${escapeHtml(item.ended_at || "未结束")}</div>
          <div class="content">
            <span class="pill">${item.message_count} messages</span>
            <span class="pill">${item.journal_count} journals</span>
          </div>
          <button type="button" onclick="window.loadSession('${escapeHtml(item.id)}')">查看详情</button>
        </article>
      `);
    }

    function renderMemories(items) {
      if (!items.length) {
        dataList.className = "";
        dataList.innerHTML = '<div class="empty">还没有保存的记忆。</div>';
        return;
      }
      const groups = new Map();
      for (const item of items) {
        const key = item.category || "uncategorized";
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(item);
      }
      dataList.className = "stack";
      dataList.innerHTML = [...groups.entries()].map(([category, memories]) => `
        <section>
          <h2 class="group-title">${escapeHtml(category)} · ${memories.length}</h2>
          <div class="grid">
            ${memories.map(item => `
              <article class="card">
                <h3>${escapeHtml(item.content)}</h3>
                <div class="meta">subcategory: ${escapeHtml(item.subcategory || "general")}</div>
                <div class="meta">status: ${escapeHtml(item.status || "active")} · importance: ${item.importance} · confidence: ${item.confidence}</div>
                <div class="meta">source session: ${escapeHtml(shortId(item.source_session_id))}</div>
                <div class="meta">updated: ${escapeHtml(item.updated_at)}</div>
                <div>${(item.keywords || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}</div>
                <div class="content">证据：${escapeHtml(item.evidence)}</div>
                ${item.merge_note ? `<div class="meta">merge note: ${escapeHtml(item.merge_note)}</div>` : ""}
                <button type="button" onclick="window.loadSession('${escapeHtml(item.source_session_id)}')">查看来源 Session</button>
              </article>
            `).join("")}
          </div>
        </section>
      `).join("");
    }

    function renderJournals(items) {
      renderList(items, item => `
        <article class="card">
          <h3>Journal ${escapeHtml(shortId(item.session_id))}</h3>
          <div class="meta">session: ${escapeHtml(item.session_id)}</div>
          <div class="meta">created: ${escapeHtml(item.created_at)}</div>
          <div class="content">${escapeHtml(item.summary)}</div>
          <div>${(item.keywords || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}</div>
          <div class="meta">下一步：${escapeHtml(item.suggested_next_step)}</div>
          <button type="button" onclick="window.loadSession('${escapeHtml(item.session_id)}')">查看关联 Session</button>
        </article>
      `);
    }

    function renderMessages(items) {
      renderList(items, item => `
        <article class="card">
          <h3>${item.role === "user" ? "你" : "小鹿"}</h3>
          <div class="meta">session: ${escapeHtml(shortId(item.session_id))} · ${escapeHtml(item.created_at)}</div>
          <div class="meta">model: ${escapeHtml(item.model || "-")}</div>
          <div class="content">${escapeHtml(item.content)}</div>
        </article>
      `);
    }

    async function loadData(view) {
      activeDataView = view;
      dataButtons.forEach(button => button.classList.toggle("active", button.dataset.view === view));
      dataList.className = "";
      dataList.innerHTML = '<div class="empty">加载中...</div>';
      try {
        const data = await get("/api/data?type=" + encodeURIComponent(view));
        if (view === "sessions") renderSessions(data.items);
        if (view === "memories") renderMemories(data.items);
        if (view === "journals") renderJournals(data.items);
        if (view === "messages") renderMessages(data.items);
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    }

    window.loadSession = async function(sessionId) {
      dataButtons.forEach(button => button.classList.remove("active"));
      dataList.className = "";
      dataList.innerHTML = '<div class="empty">加载 session 详情...</div>';
      try {
        const data = await get("/api/session_detail?id=" + encodeURIComponent(sessionId));
        dataList.className = "grid";
        dataList.innerHTML = [
          `<article class="card"><h3>Messages</h3><div class="content">${data.messages.map(m => `<b>${m.role === "user" ? "你" : "小鹿"}</b>\\n${escapeHtml(m.content)}`).join("\\n\\n")}</div></article>`,
          `<article class="card"><h3>Journals</h3><div class="content">${data.journals.map(j => escapeHtml(j.summary)).join("\\n\\n") || "无"}</div></article>`
        ].join("");
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    }

    chatTab.addEventListener("click", () => switchMainView("chat"));
    dataTab.addEventListener("click", () => switchMainView("data"));
    refreshData.addEventListener("click", () => loadData(activeDataView));
    cleanupSessions.addEventListener("click", async () => {
      try {
        const data = await post("/api/cleanup_empty_sessions", {});
        dataList.innerHTML = '<div class="empty">已清理 ' + data.deleted + ' 个空 session。</div>';
        await loadData("sessions");
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    });
    dataButtons.forEach(button => button.addEventListener("click", () => loadData(button.dataset.view)));

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
            if path == "/api/cleanup_empty_sessions":
                deleted = self.app.orchestrator.store.delete_empty_sessions()
                self.respond_json({"deleted": deleted})
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

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            settings = get_settings()
            html = HTML.replace("__WEB_TIMEOUT_MS__", str(settings.web_timeout_ms))
            self.respond_html(html)
            return
        try:
            if path == "/api/data":
                self.respond_data()
                return
            if path == "/api/session_detail":
                self.respond_session_detail()
                return
            self.send_error(404)
        except Exception as error:
            self.logger.exception("http get error path=%s", path)
            self.respond_json({"error": str(error)}, status=500)

    def respond_data(self) -> None:
        query = urlparse(self.path).query
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        data_type = params.get("type", "sessions")
        store = self.app.orchestrator.store
        if data_type == "sessions":
            items = store.list_sessions()
        elif data_type == "memories":
            items = store.list_memories()
        elif data_type == "journals":
            items = store.list_journals()
        elif data_type == "messages":
            items = store.list_messages()
        else:
            self.respond_json({"error": f"unknown data type: {data_type}"}, status=400)
            return
        self.respond_json({"items": items})

    def respond_session_detail(self) -> None:
        query = urlparse(self.path).query
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        session_id = params.get("id")
        if not session_id:
            self.respond_json({"error": "missing session id"}, status=400)
            return
        store = self.app.orchestrator.store
        self.respond_json(
            {
                "messages": store.list_messages(session_id=session_id),
                "journals": store.list_journals(session_id=session_id),
            }
        )

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
