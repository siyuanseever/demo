# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Identity

**小动物夜谈会** — a personal macOS app for emotional wellness, daily reflection, and gentle companionship.

- A personal-use Mac app (not a commercial product)
- Core features: daily conversation, emotion check-in, life recording, timed reminders
- Two runtimes: **SwiftUI Mac App** (primary) + **Python backend** (data/LLM baseline)
- Currently: Mac Catalyst, migrating toward native macOS (see ROADMAP.md N0-N5)
- Primary dev tools: Claude Code + Codex

The Python backend (`data/app.db`) is the authoritative data source. The Mac app's sandboxed SQLite is a cache synced via local-network API.

## How Claude Code Should Work Here

You are a **pair programmer** helping a solo developer build a personal Mac app. Your job is to be helpful, practical, and careful:

- **Understand before changing.** Read relevant code and docs before making edits.
- **Keep changes small.** One logical change per commit. Don't refactor and add features in the same diff.
- **Verify your work.** Run the appropriate gate commands after code changes (see below). Don't skip this.
- **Be honest about uncertainty.** If you're not sure about something — especially around safety logic, user data, or architectural decisions — say so and ask.
- **Respect the project's character.** This is a warm, gentle app about emotional wellness. Code and copy should reflect that tone.

## Common Commands

### Python Backend

```bash
# Start Web UI (http://127.0.0.1:8765)
python3 -m app.web

# CLI mode
python3 -m app.main

# Test mode (no real LLM calls)
LLM_PROVIDER=fake python3 -m app.web

# View logs
tail -f logs/app.log
```

### Validation (see AGENTS.md §4 for gate criteria)

```bash
# Syntax check (Gate 0)
python3 -m compileall app

# SSE/JS contract check
python3 -m app.evaluation.check_sse_stream

# Full evaluation suite (Gate 1) — 8 dimensions, ≥95% pass required
python3 -m app.evaluation.runner

# Diagnose test failures
python3 -m app.evaluation.diagnose

# Manual eval (Gate 4)
python3 -m app.evaluation.manual_eval
```

### Post-Change Validation

```bash
# Python changes
python3 -m compileall app && python3 -m app.evaluation.runner

# web.py changes (includes JS)
python3 -m compileall app && python3 -m app.evaluation.check_sse_stream && python3 -m app.evaluation.runner

# Prompt changes
python3 -m compileall app && python3 -m app.evaluation.runner && python3 -m app.evaluation.manual_eval
```

### Mac Build

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
| `app/web.py` | Web UI: Quart HTTP routes, embedded HTML/CSS/JS, SSE streaming |
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

The Mac app either calls DeepSeek directly (`LocalDeepSeekService`) or syncs with the Python backend over local network.

## Key Conventions

- Python: 3.12+, 4-space indent, snake_case
- Git commits: `type(scope): summary` (conventional commits)
- API keys in `.env` (template: `.env.example`), never committed
- `data/` and `logs/` are gitignored (may contain private conversation data)
- Character assets: lowercase-hyphenated filenames (`mianmian-sheep-cozy.webp`)

## Active Incidents

- **MAC-MEM-GROWTH-001**: Memory growth to ~65GB — see `docs/automation/mac-memory-incident-playbook.md`
- **Mac freeze on send**: See `docs/automation/mac-freeze-incident-playbook.md`

## Reference Files

- `AGENTS.md` — Engineering guide: quality gates, dev workflow, conventions
- `plan.md` — Current phase plan
- `ROADMAP.md` — Long-term N0-N5 native macOS migration
- `TODO.md` — Detailed task breakdown
- `status.md` — Current status and known issues
