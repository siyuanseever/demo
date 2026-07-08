# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**小动物夜谈会** — a psychological companion chat app with two runtimes:

- **Python backend** (`app/`) — Web UI (Quart/SSE), CLI, LLM orchestration, memory/knowledge store, evaluation framework
- **SwiftUI app** (`ios/XiaodongwuYetanhui/`) — Mac Catalyst app (migrating toward native macOS per Roadmap N0-N5), currently the primary product surface

The Python backend (`data/app.db`) is the authoritative data source. The Mac app's sandboxed SQLite is a cache synced via local-network API.

## Common Commands

### Python Backend

```bash
# Start Web UI (default: http://127.0.0.1:8765)
python3 -m app.web

# CLI mode
python3 -m app.main

# Test mode (no real LLM calls)
LLM_PROVIDER=fake python3 -m app.web

# DeepSeek connectivity test
python3 -m app.ping_deepseek

# View logs
tail -f logs/app.log
```

### Validation (see AGENTS.md §4 for gate criteria)

```bash
# Syntax check (Gate 0)
python3 -m compileall app

# SSE/JS contract check
python3 -m app.evaluation.check_sse_stream

# Full evaluation suite (Gate 1) — 8 dimensions, requires ≥95% pass
python3 -m app.evaluation.runner

# Diagnose test failures
python3 -m app.evaluation.diagnose

# Manual eval (Gate 4)
python3 -m app.evaluation.manual_eval
```

### Standard post-change validation

```bash
# Python changes
python3 -m compileall app && python3 -m app.evaluation.runner

# web.py changes (includes JS)
python3 -m compileall app && python3 -m app.evaluation.check_sse_stream && python3 -m app.evaluation.runner

# Prompt changes
python3 -m compileall app && python3 -m app.evaluation.runner && python3 -m app.evaluation.manual_eval
```

### Mac (Catalyst) Build

```bash
# Build and launch via script
./scripts/run_mac.sh

# Manual xcodebuild
xcodebuild -project ios/XiaodongwuYetanhui.xcodeproj \
  -scheme XiaodongwuYetanhui \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath ios/DerivedData-Mac \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Architecture

### Python Backend (`app/`)

| Module | Purpose |
|--------|---------|
| `app/web.py` | Web UI: Quart HTTP routes, embedded HTML/CSS/JS, SSE streaming (~155KB monolithic) |
| `app/main.py` | CLI entry point |
| `app/agents/orchestrator.py` | Session orchestration, conversation logic, turn planning |
| `app/agents/safety.py` | Content safety checks |
| `app/llm/base.py` | LLM client abstraction |
| `app/llm/deepseek.py` | DeepSeek adapter (streaming, thinking toggle) |
| `app/llm/fake.py` | Fake LLM for testing |
| `app/memory/store.py` | SQLite-based memory CRUD with 8-category taxonomy |
| `app/memory/schema.py` | Database schema definition |
| `app/knowledge/` | Psychology knowledge cards (JSON), retrieval, taxonomy |
| `app/prompts/` | Markdown prompt templates for LLM calls |
| `app/characters.py` | 6 companion character definitions (绵绵羊, 石石龟, etc.) |
| `app/config.py` | Environment-based configuration |
| `app/intent/` | Intent recognition |
| `app/evaluation/` | Test framework: runner, accuracy, robustness, completeness, diagnose, manual_eval |

Key design: 4-role response structure — empathy → need → main → anchor. Group-auto role selection uses rule-based routing (no extra LLM call).

### SwiftUI App (`ios/XiaodongwuYetanhui/`)

| Path | Purpose |
|------|---------|
| `App/XiaodongwuYetanhuiApp.swift` | App entry point |
| `App/AppRootView.swift` | Root view with tab navigation |
| `Views/MacPrototypeView.swift` | Primary Mac chat UI (main development surface) |
| `Views/ChatView.swift` | Chat interface |
| `Views/SettingsView.swift` | Settings (API key, sync config) |
| `Views/EmotionCheckInView.swift` | Emotion check-in flow |
| `Views/MemoryListView.swift` | Memory browsing |
| `Views/StateOverviewView.swift` | User state overview |
| `Views/StarMapView.swift` | Star map visualization |
| `Views/CompanionGardenView.swift` | Companion garden |
| `Views/InteractionViews.swift` | Interaction components |
| `Views/SharedViews.swift` | Shared/reusable views |
| `Services/LocalDeepSeekService.swift` | Direct DeepSeek API calls |
| `Services/ChatService.swift` | Chat logic |
| `Services/SQLiteDatabase.swift` | Local SQLite (sandbox cache) |
| `Services/CompanionStore.swift` | Companion state management |
| `Services/SecureSettingsStore.swift` | Keychain-based settings |
| `Services/RecommendationService.swift` | Content recommendations |
| `Services/SendInstrumentation.swift` | Send-path instrumentation for freeze debugging |

### Data Flow

```
User Input → orchestrator.py → safety.py → LLM (DeepSeek) → response
                ↓                                    ↓
          memory/store.py                    prompt templates
          knowledge/retriever.py             characters.py
```

iOS app either calls DeepSeek directly (`LocalDeepSeekService`) or syncs with the Python backend over local network (HTTP API with sync token auth).

## Key Conventions

- Python: 3.12+, 4-space indent, snake_case
- Git commits: `type(scope): summary` (conventional commits, often Chinese descriptions)
- API keys in `.env` (template: `.env.example`), never committed
- `data/` and `logs/` are gitignored (may contain private conversation data)
- Character assets: lowercase-hyphenated filenames (`mianmian-sheep-cozy.webp`)

## Critical Active Incidents

- **MAC-MEM-GROWTH-001**: Memory growth to ~65GB — see `docs/automation/mac-memory-incident-playbook.md`
- **Mac freeze on send**: See `docs/automation/mac-freeze-incident-playbook.md`

## Reference Files

- `AGENTS.md` — Full governance: gate criteria, agent roles (Checker/Fixer/Executor/PM), worktree protocol, incident playbooks
- `plan.md` — Current phase plan (Catalyst stabilization)
- `ROADMAP.md` — Long-term N0-N5 native macOS migration
- `TODO.md` — Detailed task breakdown
- `status.md` — Current status and known issues
- `docs/automation/` — Automation protocol, agent prompts, incident playbooks
