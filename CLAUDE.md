# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Geary-Gemini is a fork of GNOME Geary (GTK3 desktop email client) with Google Gemini AI integration. Written in Vala (compiles to C/GObject), built with Meson/Ninja, packaged as a `.deb` via Docker.

## Build Commands

### Docker package build (preferred — produces `.deb` in `dist/`)
```bash
docker compose up --build --abort-on-container-exit
```

### Local dev build
```bash
meson setup /tmp/build --prefix=/usr --buildtype=release -Dprofile=release
ninja -C /tmp/build
```

### Run tests (non-GUI suites used in CI/container)
```bash
meson test -C /tmp/build --no-rebuild --print-errorlogs \
  --suite geary:engine-tests \
  --suite geary:mail-merge-test \
  --suite vala-unit:tests
```

## Architecture

**Two-layer structure:**
- `src/engine/` — Core email engine (IMAP/SMTP protocol, SQLite database, email parsing via GMime)
- `src/client/` — GTK3 UI application (accounts, composer, conversation views, sidebar, plugins)

**Gemini integration (the custom layer):**
- `src/client/gemini/gemini-service.vala` — Subprocess wrapper for `gemini-cli`. Handles auth, streaming chat, translate, summarize. Prompts passed via stdin (not CLI args). Uses `--output-format stream-json` for structured streaming.
- `src/client/gemini/gemini-sidebar.vala` — Chat UI widget with message history, thinking/tool panel, markdown-to-Pango rendering, streaming display.
- `ui/gemini-sidebar.ui` — Sidebar layout XML
- `ui/components-headerbar-conversation.ui` — AI toggle button in header bar
- MCP/D-Bus bridge is **removed** from runtime. Direct CLI subprocess calls only. Do not reintroduce without explicit approval.

**Key app entry points:**
- `src/client/application/application-client.vala` — App singleton, owns `gemini_service`
- `src/client/application/application-main-window.vala` — Main window, creates sidebar on demand

**Tests:** `test/` mirrors `src/` structure. Uses GLib.Test via Vala test harnesses (`test-engine.vala`, `test-client.vala`). Gemini service tests in `test/client/gemini/gemini-service-test.vala`.

## Coding Conventions

- **Vala:** 4-space indent. Classes `PascalCase`, methods `snake_case`. Async: `.begin()` to start, `yield` to await. Signals: `public signal void name()`.
- **UI XML:** 2-space indent. GtkTemplate requires exact `.ui` id ↔ `[GtkChild]` field match.
- **i18n:** Preserve existing `_()` style for user-visible strings.
- **Commits:** Prefix with `fix:`, `ui:`, `refactor:`, `docs:`, `feat:`, `test:`. Concrete, user-impact oriented.
- Keep changes minimal. Avoid broad refactors unless required for stability.
- Do not swallow real failures; only suppress known non-fatal noise (e.g., `Loaded cached credentials.`, Node deprecation warnings).

## Build Gotchas

- Use `docker compose` (v2 with space), not `docker-compose` (hyphenated).
- Meson 1.10.0 has a DirectoryLock bug — pin to `< 1.10`.
- libpeas-2 needs a custom VAPI (generated from GIR, lives in `bindings/vapi/`).
- `dist/` directory needs to be world-writable (`chmod 777`) for container output.
- Build logs are very noisy; warnings are common and mostly pre-existing.

## Gemini UX Rules

- Enter = send, Ctrl+Enter = newline in chat composer.
- Thinking/tool panel above input composer, collapsed by default.
- Auth flow: capture output, extract auth URL, attempt browser launch, provide fallback text.
- Selected email context injected into prompts in-process. Scope to selected email unless user asks otherwise.
- Never hallucinate attachment contents; state limitation if extracted text unavailable.

## Reference Docs

- `AGENTS.md` — Coding agent guidance, UX rules, auth rules, done criteria
- `GEARY.md` — Gemini in-app skill contract (input/output rules, style)
- `BUILDING.md` — Original Geary build instructions and dependency list
