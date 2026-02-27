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
- Selected email context is built in-process and injected into prompts.
- Thinking/tool UI exists, but should stay user-friendly (no noisy raw internals by default).

If you reintroduce MCP/DBus, treat that as a major architecture change requiring explicit approval.

## Repo Hotspots

- `src/client/gemini/gemini-service.vala`
  - Gemini subprocess execution
  - auth status/login handling
  - stderr filtering / non-fatal warnings
  - prompt construction and selected-email context
- `src/client/gemini/gemini-sidebar.vala`
  - chat input behavior
  - thinking/tool rendering
  - streaming UX
- `ui/gemini-sidebar.ui`
  - sidebar layout and composer behavior
- `ui/components-headerbar-conversation.ui`
  - top-level AI button/icon
- `docker-compose.yml`
  - canonical package build path for `.deb`

## UX Rules (Established)

- AI icon should be assistant-like (not generic star).
- Thinking/tool panel should be above input composer.
- Tool details should be collapsed by default; expand on demand.
- Thinking text should wrap to panel width when expanded.
- Composer behavior:
  - **Enter = send**
  - **Ctrl+Enter = newline**

## Auth/Login Rules (Established)

- `Loaded cached credentials.` is informational, **not** a fatal error.
- Node deprecation warnings (e.g., punycode) should not surface as user-facing errors.
- Login flow should:
  - capture auth command output,
  - extract auth URL when present,
  - attempt browser launch,
  - provide useful fallback/error text.

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

## Known Quirks

- Build logs are very noisy; warnings are common and mostly pre-existing.
- Container builds can fail from disk pressure; prune Docker artifacts when needed.
- Auth/browser launch behavior varies by desktop/session; always provide fallback messaging.
- README may contain historical MCP notes; treat runtime source code as authority.

## Safety / Privacy

- Never exfiltrate user emails or attachment content.
- Keep prompt context scoped to selected email unless user asks otherwise.
- If attachment text is unavailable, state limitation explicitly; do not hallucinate.

## Done Criteria for Gemini-related changes

1. Builds successfully via `docker compose`.
2. `.deb` produced in `dist/`.
3. No user-facing false errors for warning-only stderr.
4. Chat UX interactions (send/newline, wrapping, panel behavior) match rules above.
