# AGENTS.md

Agent guidance for `geary-gemini`.

This repository is a Geary fork with Gemini CLI integration.
Use this file as the operational context for coding agents.

## Project Scope

- Base app: GNOME Geary (Vala/GTK3 + Meson/Ninja)
- Custom layer: Gemini sidebar, chat UX, auth/login flow, prompt-based actions
- Packaging: Docker Compose build that outputs a `.deb` and bundles Node + `@google/gemini-cli`

## Current Architecture Decisions (Important)

- **MCP + D-Bus bridge is removed for runtime usage.**
- Gemini requests are executed through direct CLI prompt calls in `Gemini.Service`.
- Prompts are passed via **stdin** (`-p -`) to avoid exposing email content in `/proc/cmdline`.
- Auth output is **streamed line-by-line** so the browser URL opens immediately (not buffered until exit).
- Selected email context is built in-process and injected into prompts.
- Binary attachments (PDFs, images) are passed to gemini-cli using `@<path>` syntax for multimodal analysis.
- Thinking/tool UI exists, but should stay user-friendly (no noisy raw internals by default).
- **Account switching**: active Gemini account is persisted in `~/.gemini/google_accounts.json` and selected via a gear-icon popover that lists Geary's Google accounts.

If you reintroduce MCP/DBus, treat that as a major architecture change requiring explicit approval.

## Repo Hotspots

- `src/client/gemini/gemini-service.vala`
  - Gemini subprocess execution (stdin-based prompt delivery)
  - streaming auth output + URL extraction
  - stderr filtering / non-fatal warnings
  - prompt construction and selected-email context
  - active account persistence (`~/.gemini/google_accounts.json`)
  - multimodal attachment handling (`@<path>` syntax)
- `src/client/gemini/gemini-sidebar.vala`
  - chat input behavior
  - thinking/tool rendering
  - streaming UX
  - account selector popover (gear icon)
  - markdown-to-Pango rendering
- `ui/gemini-sidebar.ui`
  - sidebar layout, composer, and account selector UI
- `ui/components-headerbar-conversation.ui`
  - top-level AI button/icon
- `test/client/gemini/gemini-service-test.vala`
  - unit tests for URL extraction, warning filtering, truncation
- `docker-compose.yml`
  - canonical package build path for `.deb`

## UX Rules (Established)

- AI icon should be assistant-like (not generic star).
- Thinking/processing status is a **single-line bar** (spinner + ellipsized label) above the input — no expandable details panel.
- Streaming status shows tool names and response snippets inline, auto-truncated to fit.
- Sidebar opens at **50/50 split** with the email view, minimum 500px, user-resizable via drag handle.
- Composer behavior:
  - **Enter = send**
  - **Ctrl+Enter = newline**

## Auth/Login Rules (Established)

- `Loaded cached credentials.` is informational, **not** a fatal error.
- Node deprecation warnings (e.g., punycode) should not surface as user-facing errors.
- Auth output is streamed line-by-line; browser opens as soon as the URL is captured.
- Login flow should:
  - stream auth command output (not buffer until exit),
  - extract auth URL when present (regex strips trailing punctuation),
  - attempt browser launch immediately,
  - provide useful fallback/error text.
- Account selection uses a **gear-icon popover** listing Geary's Google accounts.
- `/login` chat command redirects users to the gear icon rather than triggering login directly.
- The standalone "Login with Google" button is hidden; account selection is the entry point.

## Build & Test Commands

### Local package build (preferred)
```bash
docker compose up --build --abort-on-container-exit
```

### Build artifact
- Output deb path:
  - `dist/geary-gemini_46.0_amd64.deb`

### Typical dev checks
```bash
# configure + build
meson setup /tmp/build --prefix=/usr --buildtype=release -Dprofile=release
ninja -C /tmp/build

# non-GUI tests used in container flow
meson test -C /tmp/build --no-rebuild --print-errorlogs \
  --suite geary:engine-tests \
  --suite geary:mail-merge-test \
  --suite vala-unit:tests
```

### Gemini-specific unit tests
- `test/client/gemini/gemini-service-test.vala` covers URL extraction, warning filtering, and prompt truncation.
- These run as part of the `vala-unit:tests` suite.
- Key methods under test are marked `internal` for test access: `extract_first_url`, `filter_non_fatal_warnings`, `truncate_for_prompt`.

## PR / Branch Workflow

- Prefer a single active feature PR at a time unless asked otherwise.
- Keep commit messages concrete (`fix:`, `ui:`, `refactor:`) and user-impact oriented.
- When a PR includes UI changes, attach exact before/after behavior in PR description.
- If build fails, include first failing compiler/runtime line in status update.

## Coding Conventions

- Keep Vala changes explicit and minimal.
- Avoid broad refactors unless required for stability.
- Preserve existing i18n style (`_()` for user-visible strings).
- Do not swallow real failures; only suppress known non-fatal noise.
- Prefer deterministic behavior over clever abstractions.
- **Async widget safety**: all async callbacks and signal handlers in the sidebar must guard with `if (!this.get_mapped()) return;` before touching widget properties. The sidebar can be destroyed while callbacks are in-flight.

## Known Quirks

- Build logs are very noisy; warnings are common and mostly pre-existing.
- Container builds can fail from disk pressure; prune Docker artifacts when needed.
- Auth/browser launch behavior varies by desktop/session; always provide fallback messaging.
- All stderr lines are read (not just the first); real errors are separated from non-fatal noise.
- README may contain historical MCP notes; treat runtime source code as authority.

## Safety / Privacy

- Never exfiltrate user emails or attachment content.
- Prompts are passed via stdin to avoid leaking email content in process arguments.
- Keep prompt context scoped to selected email unless user asks otherwise.
- If attachment text is unavailable, state limitation explicitly; do not hallucinate.

## Done Criteria for Gemini-related changes

1. Builds successfully via `docker compose`.
2. `.deb` produced in `dist/`.
3. No user-facing false errors for warning-only stderr.
4. Chat UX interactions (send/newline, wrapping, panel behavior) match rules above.
