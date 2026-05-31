# Repository Guidelines

## Project Structure & Module Organization

This repository is a Python stdlib demo for **小动物夜谈会**, a psychological companion chat app.

- `app/web.py` contains the local Web UI, HTTP routes, embedded CSS, and browser JavaScript.
- `app/agents/` contains orchestration and safety logic.
- `app/llm/` contains model adapters, including DeepSeek and the fake model.
- `app/memory/` contains SQLite schema and persistence code.
- `app/knowledge/` contains knowledge/content cards and retrieval helpers.
- `app/prompts/` contains prompts sent to the LLM.
- `app/static/` stores avatars, cozy status images, and UI background assets.
- `docs/`, `TODO.md`, and `ROADMAP.md` document product direction and implementation notes.
- Runtime files live in `data/app.db` and `logs/app.log`; avoid committing private data.

## Build, Test, and Development Commands

- `python3 -m app.web` starts the local Web UI.
- `python3 -m app.main` runs the CLI conversation flow.
- `python3 -m app.ping_deepseek` checks DeepSeek API connectivity.
- `python3 -m compileall app` validates Python syntax.
- `node --check /private/tmp/xiaolu-web-check.js` validates extracted browser JavaScript when editing `app/web.py`.

## Coding Style & Naming Conventions

Use Python 3.12-compatible code and keep changes small. Prefer clear functions, explicit names, and simple control flow. Follow existing style: 4-space indentation, snake_case for Python names, and descriptive JSON keys. Keep UI changes in `app/web.py` unless a broader frontend split is intentional.

For character assets, use stable lowercase hyphenated filenames, for example `mianmian-sheep-cozy.webp`.

## Testing Guidelines

There is no full automated test suite yet. Always run `python3 -m compileall app` after Python changes. When editing embedded JavaScript, extract the `<script>` block from `app/web.py`, replace template placeholders, and run `node --check`.

Manual checks should cover: starting a session, sending a message, ending/summarizing a session, viewing dashboard data, switching roles, and group-auto role selection.

## Commit & Pull Request Guidelines

Recent history uses mixed conventional and Chinese commit messages, such as `feat(web): ...`, `style(control-panel): ...`, and `docs(prompts): ...`. Prefer `type(scope): summary` when possible.

Pull requests should include: purpose, key files changed, validation commands run, screenshots for UI changes, and notes about any prompt, memory, or safety behavior changes.

## Security & Configuration Tips

Keep API keys in `.env`; never hard-code or commit secrets. Use `.env.example` for new configuration names. Be careful with `data/app.db` and `logs/app.log`, because they may contain private conversation data.
