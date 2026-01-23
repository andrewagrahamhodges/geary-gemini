
Geary: Send and receive email
=============================

![Geary icon](https://gitlab.gnome.org/GNOME/geary/raw/HEAD/icons/hicolor/scalable/apps/org.gnome.Geary.svg)

Geary is an email application built around conversations, for the
GNOME desktop. It allows you to read, find and send email with a
straight-forward, modern interface.

Visit https://gitlab.gnome.org/GNOME/geary/-/wikis for more information.

**GitHub users please note**: Bug reports, code contributions and
translations are managed using GNOME's infrastructure, so we cannot
accept tickets or pull requests on GitHub. Please see the links below
for more information.

![Geary displaying a conversation](https://static.gnome.org/appdata/geary/geary-40-main-window.png)

Building & Licensing
--------------------

### Docker Build (Recommended)

Build Geary-Gemini without installing any local dependencies:

```bash
# Build the application
docker compose run --rm build

# Run tests
docker compose run --rm test

# Create .deb package (output in ./dist/)
docker compose run --rm package

# Interactive shell for debugging
docker compose run --rm shell

# Clean build cache
docker compose run --rm clean
```

### Local Build

Please consult the [BUILDING.md](./BUILDING.md) and
[COPYING](./COPYING) files for more information about building Geary
and the licence granted by its copyright holders for redistribution.

Getting in Touch
----------------

 * Geary wiki: https://gitlab.gnome.org/GNOME/geary/-/wikis
 * Support and discussion: See the `geary` tag on [GNOME Discourse](https://discourse.gnome.org/tags/c/applications/7/geary)
 * Matrix channel: [#geary:gnome.org](https://gnome.element.io/#/room/#geary:gnome.org)

Code Of Conduct
---------------

As Geary is part of the GNOME community (and is hosted on its infrastructure),
it follows the [GNOME Code of Conduct](https://conduct.gnome.org/). All
communications in project spaces are expected to adhere to it.

Contributing to Geary
---------------------

Want to help improve Geary? Here are some ways to contribute:

 * Bug reporting: https://gitlab.gnome.org/GNOME/geary/-/wikis/Reporting-Bugs-and-Requesting-Features
 * Translating:   https://gitlab.gnome.org/GNOME/geary/-/wikis/Translating
 * Development:   https://gitlab.gnome.org/GNOME/geary/-/wikis/Development
 * Donate:        https://donate.gnome.org

---
Copyright © 2016 Software Freedom Conservancy Inc.
Copyright © 2017-2020 Michael Gratton <mike@vee.net>

---

## AI Context & Session State

> **Purpose:** Persistent context for AI coding agents working on this fork.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GEARY-GEMINI APPLICATION                    │
│                      (GTK 3 Desktop Client)                         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
┌───────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   UI Layer    │    │  Engine Layer   │    │  Data Layer     │
│  (GTK/Vala)   │    │  (IMAP/SMTP)    │    │  (SQLite FTS)   │
│               │    │                 │    │                 │
│ - Composers   │    │ - Account mgmt  │    │ - Conversations │
│ - Conversat.  │    │ - Folder sync   │    │ - Full-text idx │
│ - Main Window │    │ - Email send    │    │ - Attachments   │
│ - Gemini UI   │    │                 │    │                 │
│ - Gemini Chat │    │                 │    │                 │
└───────────────┘    └─────────────────┘    └─────────────────┘
        │                      │                      │
        └──────────────────────┼──────────────────────┘
                               ▼
                    ┌─────────────────────┐
                    │   External Services │
                    │  - GNOME Online Acc │
                    │  - libsecret        │
                    │  - WebKitGTK        │
                    │  - gemini-cli (AI)  │
                    └─────────────────────┘
```

**Folder Structure:**
```
geary-gemini/
├── src/
│   ├── client/          # GTK UI application
│   │   ├── accounts/    # Account setup/management
│   │   ├── application/ # Main window, controller (+ Gemini integration)
│   │   ├── composer/    # Email composition (+ AI helper)
│   │   ├── components/  # Reusable UI components (+ headerbar with Gemini toggle)
│   │   ├── conversation-list/
│   │   ├── conversation-viewer/
│   │   └── gemini/      # Gemini AI integration
│   │       ├── gemini-service.vala   # gemini-cli subprocess wrapper
│   │       └── gemini-sidebar.vala   # Chat sidepane widget
│   ├── engine/          # Core email engine (IMAP/SMTP)
│   │   ├── api/         # Public engine API
│   │   ├── imap/        # IMAP protocol implementation
│   │   ├── smtp/        # SMTP protocol implementation
│   │   └── db/          # SQLite database layer
│   └── geary.vala       # Application entry point
├── ui/                  # GtkBuilder UI definitions (.ui files)
│   ├── application-main-window.ui     # Main window (+ Gemini sidebar container)
│   ├── components-conversation-actions.ui  # Translate/Summarize buttons
│   ├── components-headerbar-conversation.ui  # Gemini toggle button
│   ├── composer-editor.ui             # AI helper prompt bar
│   └── gemini-sidebar.ui              # Chat sidepane UI
├── po/                  # Translations
├── test/                # Unit tests
├── bindings/vapi/       # Custom Vala bindings (libpeas-2)
├── build-aux/           # Build scripts (make-deb.sh)
├── dist/                # Output directory for .deb packages
├── meson.build          # Build configuration
└── docker-compose.yml   # Docker build orchestration
```

### Tooling & Tech Stack

| Component | Technology | Version/Notes |
|-----------|------------|---------------|
| Language | Vala | Compiles to C, GObject-based |
| UI Toolkit | GTK 3 | + libhandy for modern widgets |
| Build System | Meson + Ninja | `meson build && ninja -C build` |
| Email Parsing | GMime 3.0 | MIME handling |
| Database | SQLite 3 | FTS3 + FTS5 for search |
| HTML Rendering | WebKitGTK 4.1 | Email body display |
| Accounts | GNOME Online Accounts | OAuth integration |
| Secrets | libsecret | Credential storage |
| Spell Check | gspell / enchant2 | Composition |
| Plugins | libpeas-2 | Plugin system (requires GIR bindings) |
| Crypto | gcr-4, gck-2 | Keyring/certificate handling |
| AI Backend | gemini-cli | Google Gemini via subprocess (npm package) |

**Docker Build (Recommended):**
```bash
docker compose run --rm build    # Configure + compile
docker compose run --rm test     # Run unit tests
docker compose run --rm package  # Create .deb
docker compose run --rm shell    # Debug shell
docker compose run --rm clean    # Clear build cache
```

### Environment Variables

| Key | Purpose |
|-----|---------|
| `G_MESSAGES_DEBUG` | Set to `all` or `Geary` for debug logging |
| `GTK_DEBUG` | GTK debugging flags |
| `GEARY_DEBUG` | Geary-specific debug flags |
| `LANG` | System locale - used by Gemini translate feature to detect target language |

*No API keys needed - gemini-cli handles authentication via Google OAuth*

### Active Objectives

**Current Mission:** Integrate Gemini AI capabilities into Geary

**Features Implemented:**
1. **Translate Button** - Next to reply/forward buttons, translates email to system language via gemini-cli
2. **Summarize Button** - Next to translate button, generates email summary via gemini-cli
3. **Composer AI Helper** - Gmail-style button in composer toolbar with inline prompt bar
4. **GeminiService** - Core service class with auto-install logic for gemini-cli
5. **Gemini Chat Sidepane** - Full chat widget with message history and loading indicators
6. **Sidebar Toggle Button** - Star icon button in conversation headerbar to toggle sidepane

**Integration Approach:**
- Use `gemini-cli` as the AI backend (subprocess calls)
- Auto-install gemini-cli via npm on first use (like Zed editor)
- Authentication via Google OAuth (handled by gemini-cli)
- All AI features are additive (new buttons/pane), minimal changes to core Geary

**Build Strategy:**
- Fully containerized build (Ubuntu 25.10 base for development)
- Docker Compose orchestrates build environment
- Outputs `.deb` package for installation

**Installation - Kill Geary Properly:**

Geary runs background processes and may auto-restart. To fully kill it before installing:

```bash
# 1. Disable any autostart
systemctl --user stop geary.service 2>/dev/null
systemctl --user disable geary.service 2>/dev/null

# 2. Kill ALL Geary processes (including background workers)
pkill -9 -f geary
killall -9 geary 2>/dev/null

# 3. Wait and verify it's dead
sleep 2
pgrep -f geary && echo "STILL RUNNING - try logging out and back in" || echo "Geary is dead"

# 4. Install the new version
sudo apt install --reinstall ./dist/geary-gemini_46.0_amd64.deb

# 5. Start fresh
geary &
```

**Nuclear option** - if it still won't die:
```bash
# Log out of GNOME session completely, then log back in
# OR reboot
sudo reboot
```

### Current Blockers

*None - Translate, Summarize, and Composer AI buttons fully functional!*

### Recent Accomplishments

1. [x] Define feature specifications (Translate, Summarize, Gemini Chat Sidepane)
2. [x] Create Dockerfile with all build dependencies (now Ubuntu 25.10)
3. [x] Create docker-compose.yml for build orchestration
4. [x] Add debian packaging configuration to produce .deb file
5. [x] Fix Meson version issues and libpeas-2 vapi generation
6. [x] Fix messaging-menu plugin bug (APP_ID reference error)
7. [x] Complete successful Docker build
8. [x] **Created GeminiService class** (`src/client/gemini/gemini-service.vala`)
   - Auto-install gemini-cli via npm
   - Google OAuth authentication flow
   - Methods: translate(), summarize(), help_compose(), chat()
9. [x] **Added Translate & Summarize buttons** to conversation actions UI
   - New buttons in `ui/components-conversation-actions.ui`
   - Action handlers in `application-main-window.vala`
10. [x] **Added Gmail-style AI helper to composer**
    - AI help button (star icon) in composer toolbar
    - Inline prompt bar with Cancel/Create buttons
    - Signal for AI text generation
11. [x] **Created Gemini Chat Sidepane** (`src/client/gemini/gemini-sidebar.vala`)
    - Interactive chat interface with message history
    - Auto-install prompt for gemini-cli when not installed
    - Loading indicators during AI responses
    - Close button to hide sidebar
12. [x] **Added sidebar toggle button** to conversation headerbar
    - Star icon button triggers `win.toggle-gemini-sidebar` action
13. [x] **Integrated sidebar into main window**
    - Added GtkRevealer container for sidebar in `ui/application-main-window.ui`
    - GeminiService initialization in MainWindow constructor
    - Toggle action creates sidebar on-demand and shows/hides it
14. [x] Updated meson.build and gresource.xml with new files
15. [x] Verified build succeeds and .deb package creation works
16. [x] **Wired Translate button to GeminiService** - Extracts email text and calls translate_to_system_language()
17. [x] **Wired Summarize button to GeminiService** - Extracts email text and calls summarize()
18. [x] **Added AI result dialog** - Modal dialog with scrollable text and Copy to Clipboard button
19. [x] **Wired Composer AI Helper** - Connected editor signal to GeminiService.help_compose(), inserts result as HTML
20. [x] **Moved GeminiService to Application.Client** - App-wide singleton for all components to access
21. [x] **Created MCP Server for email tools** (`mcp-server/`)
    - Node.js MCP server implementing Model Context Protocol
    - Communicates with Geary via D-Bus
    - Tools: `list_emails`, `get_selected_email`, `read_email`, `search_emails`, `select_email`
    - Allows gemini-cli to access and interact with emails
22. [x] **Created D-Bus service for email operations** (`src/client/gemini/gemini-dbus-service.vala`)
    - Exposes `org.gnome.Geary.EmailTools` interface on session bus
    - Methods: ListEmails, GetSelectedEmail, ReadEmail, SearchEmails, SelectEmail
    - JSON-based API for MCP server communication
23. [x] **Integrated D-Bus service into application**
    - Added `email_tools_service` property to `Application.Client`
    - Service registered on startup, unregistered on shutdown
    - Main window reference passed for email access
24. [x] **Added MCP server auto-configuration**
    - `GeminiService.configure_mcp_server()` writes `~/.gemini/settings.json`
    - Configures `geary` MCP server pointing to bundled Node.js and server.js
    - Called on application startup
25. [x] **Added streaming output support to GeminiService**
    - New `StreamingCallback` delegate for real-time output
    - `chat_streaming()` method with line-by-line callback
    - Sidebar shows live output during AI processing
26. [x] **Enhanced sidebar with streaming and result display**
    - `update_streaming_output()` shows live AI responses in loading label
    - `show_ai_result()` for displaying translate/summarize results in sidebar
    - `start_loading()`, `update_loading()`, `stop_loading()` helper methods
27. [x] **Added dynamic build timestamp**
    - `Config.BUILD_TIME` generated at build time via Python
    - Displayed in About dialog for debugging
28. [x] **Fixed MCP server notifications/initialized handler**
    - gemini-cli sends `notifications/initialized` not just `initialized`
    - Added D-Bus environment variable to MCP subprocess config
29. [x] **Added system prompt with guardrails**
    - Default response language matches system locale
    - Assumes selected email context when not specified
    - Instructs Gemini on appropriate email assistant behavior
30. [x] **Added structured JSON streaming support**
    - `--output-format stream-json` for type-based message filtering
    - Separates "thinking" (tool_use/tool_result) from final response (message)
    - Thinking shown in loading indicator, not in final output
31. [x] **Removed translate/summarize buttons from conversation actions**
    - Chat sidebar provides better UX for these functions
    - Cleaner toolbar appearance
32. [x] **Added markdown rendering support for chat messages**
    - Updated system prompt to tell Gemini to use markdown
    - `markdown_to_pango()` converter handles bold, italic, code, headers, lists
    - AI responses rendered with Pango markup formatting
33. [x] **Made sidebar resizable with GtkPaned**
    - Replaced GtkBox with GtkPaned in `application-main-window.ui`
    - Wide handle for easy drag resizing
    - Minimum sidebar width of 280px (shrink=False)
    - Removed redundant `gemini_separator` widget
34. [x] **Enhanced thinking panel with tool activity display** (2026-01-21)
    - `StructuredStreamCallback` delegate with tool_name and tool_input_json parameters
    - Thinking panel shows detailed tool descriptions (e.g., "Listing 10 emails from INBOX...")
    - Tool items display with spinner while in progress, checkmark when complete
    - `get_tool_description()` parses tool input JSON for human-readable messages
    - `add_tool_item()`, `complete_current_tool()`, `clear_tool_items()` helper methods
35. [x] **Fixed sidebar default width** (2026-01-23)
    - Increased `gemini_sidebar_container` width_request from 280px to 360px
    - Send button now visible when sidebar first opens
36. [x] **Added attachment access for MCP server** (2026-01-23)
    - Email JSON responses now include `attachments` array with metadata (index, filename, content_type, filesize, has_file)
    - New `get_attachment_content()` D-Bus method reads attachment content
    - Returns text for text-based types, base64 for binary (with size limits)
    - Added `is_text_content_type()` helper for MIME type detection
    - New `get_attachment_content` MCP tool for Gemini to access attachments
    - Enables Gemini to summarize/translate email attachments
37. [x] **Disabled valadoc in build** (2026-01-23)
    - Added `-Dvaladoc=disabled` to meson setup in docker-compose.yml
    - Fixes build failure caused by valadoc generation errors

### Next Steps

1. [ ] Add email action tools to MCP server (archive, delete, star, label)
2. [ ] Test MCP integration end-to-end with gemini-cli
3. [ ] Add keyboard shortcut for Gemini sidebar toggle
4. [ ] Consider adding Gemini suggestions in email search
5. [ ] Add email context to Composer AI Helper when replying (currently passes null)

### Session Notes

**gemini-cli Integration Notes:**
- gemini-cli installed via: `npm install @google/gemini-cli@latest`
- Run prompts with: `gemini -p "your prompt here"`
- Auth via: `gemini auth login` (opens browser for OAuth)
- App stores local install in `~/.local/share/geary-gemini/node_modules/`
- Structured output: `gemini --output-format stream-json` for type-based message filtering

**UI Implementation Details:**
- Composer AI helper: `ui/composer-editor.ui` (GtkRevealer with prompt bar)
- Gemini sidebar toggle: `ui/components-headerbar-conversation.ui` (GtkToggleButton)
- Sidebar container: `ui/application-main-window.ui` (GtkPaned with GtkRevealer)
- Actions: `win.toggle-gemini-sidebar`, `edt.ai-help`
- Translate/Summarize buttons removed - sidebar provides better UX

**Email Text Extraction (for AI features):**
- Path: `ConversationViewer` → `current_list` → `get_reply_target()` → `email` → `get_message()` → `get_searchable_body(true)`
- Fallback: `email.get_preview_as_string()` if body not loaded
- Helper method: `MainWindow.get_displayed_email_text()` returns formatted text with From/Subject headers

**Files Created in Previous Sessions:**
- `src/client/gemini/gemini-sidebar.vala` - Chat sidebar widget class
- `ui/gemini-sidebar.ui` - Sidebar UI definition with header, chat area, input, status

**Files Modified This Session (2026-01-19):**
- `src/client/application/application-client.vala` - Added app-wide `gemini_service` property
- `src/client/application/application-main-window.vala` - Added `get_displayed_email_text()`, wired translate/summarize handlers, added `show_ai_result_dialog()`
- `src/client/composer/composer-widget.vala` - Connected `ai_generate_requested` signal to `generate_ai_content()` handler

**Files Created/Modified (2026-01-20) - MCP Integration:**
- `mcp-server/package.json` - Node.js MCP server package definition
- `mcp-server/server.js` - MCP server implementing email tools via D-Bus
- `src/client/gemini/gemini-dbus-service.vala` - D-Bus service exposing email operations
- `src/client/application/application-client.vala` - Added `email_tools_service`, D-Bus registration, MCP auto-config
- `src/client/gemini/gemini-service.vala` - Added `configure_mcp_server()`, streaming support, updated system prompt
- `src/client/gemini/gemini-sidebar.vala` - Added streaming output display, `show_ai_result()` method
- `src/client/meson.build` - Added gemini-dbus-service.vala to build
- `src/meson.build` - Added BUILD_TIME config variable
- `bindings/vapi/config.vapi` - Added BUILD_TIME declaration
- `docker-compose.yml` - Simplified to single build service, added MCP server bundling
- `ui/gemini-sidebar.ui` - Added loading_label widget for streaming output

**Files Modified (2026-01-21) - UI Improvements:**
- `mcp-server/server.js` - Fixed `notifications/initialized` handler for gemini-cli compatibility
- `src/client/gemini/gemini-service.vala` - Added D-Bus env to MCP config, stream-json output, system prompt with markdown
- `src/client/gemini/gemini-sidebar.vala` - Added `markdown_to_pango()` converter, structured JSON stream handling
- `src/client/application/application-main-window.vala` - Removed `gemini_separator` reference, translate/summarize actions
- `ui/application-main-window.ui` - Replaced GtkBox with GtkPaned for resizable sidebar
- `ui/components-conversation-actions.ui` - Removed translate/summarize buttons (gemini_buttons box)

**Files Modified (2026-01-21) - Enhanced Thinking Panel:**
- `src/client/gemini/gemini-service.vala` - Extended `StructuredStreamCallback` with tool_name and tool_input_json params
- `src/client/gemini/gemini-sidebar.vala` - Added thinking panel with tool activity: spinners, descriptions, completion states
- `ui/gemini-sidebar.ui` - Added `thinking_content_box` for dynamic tool item display

**Files Modified (2026-01-23) - Attachment Access & Sidebar Fix:**
- `ui/application-main-window.ui` - Increased sidebar width_request from 280 to 360
- `src/client/gemini/gemini-dbus-service.vala` - Added attachments to email JSON, `get_attachment_content()` method, `is_text_content_type()` helper
- `mcp-server/server.js` - Added `get_attachment_content` tool definition and handler
- `docker-compose.yml` - Added `-Dvaladoc=disabled` to meson setup

### Mental Context / Gotchas

**Build System Gotchas:**
- Use `docker compose` (v2 syntax with space), NOT `docker-compose` (v1 hyphenated)
- Meson 1.10.0 has a `DirectoryLock` bug - pin to `<1.10`
- Ubuntu 24.04 packages are behind what Geary 46.0 needs:
  - Meson 1.3.2 → needs >= 1.7 (install via pip)
  - Missing dev packages: `libgck-2-dev`, `libgcr-4-dev`, `libpeas-2-dev`
- Vala needs `.vapi` files; having the `-dev` package isn't always enough
- libpeas-2 has no system vapi - we generated one from GIR using vapigen and added to `bindings/vapi/`
- The `dist/` directory needs to be world-writable (777) for the container's builder user to write the .deb

**Project Directory Warning:**
- Working directory is `/home/andrewhodges/Documents/Projects/geary-gemini`
- Do NOT write files to `/home/andrewhodges/Documents/Projects/axelera/phantomops` - that's a different project!
- Always verify file paths before writing

**Vala/GTK Gotchas:**
- GtkTemplate requires exact match between .ui file id attributes and [GtkChild] field names
- GtkRevealer.reveal_child controls visibility with animation
- Async methods in Vala use `.begin()` to start and yield for await
- Signals declared with `public signal void name()` pattern
- `Components.InAppNotification` uses `.close()` to dismiss (not `remove_notification()`)
- ComposerWidget has no `referred` property - email context passed to `load_context()` is not stored as a field
- Access app-wide services via: `this.container.top_window.application as Application.Client`

**MCP Integration Gotchas:**
- D-Bus method names are PascalCase (e.g., `ListEmails`) but Vala uses snake_case (`list_emails`)
- MCP server communicates via JSON-RPC over stdio with gemini-cli
- D-Bus service must be registered BEFORE main window is created (or set_main_window called after)
- gemini-cli MCP config lives in `~/.gemini/settings.json` - auto-configured on app startup
- MCP server path in .deb: `/usr/share/geary-gemini/mcp-server/server.js`
- Node.js path in .deb: `/usr/share/geary-gemini/node/bin/node`
- gemini-cli sends `notifications/initialized` (not just `initialized`) - must handle both
- D-Bus environment `DBUS_SESSION_BUS_ADDRESS` must be passed to MCP subprocess via `env` in settings.json

**Streaming and Output Gotchas:**
- Use `--output-format stream-json` for structured output with message types
- JSON stream types: `tool_use` (thinking), `tool_result` (tool output), `message` (final response)
- Only `message` type with `role=assistant` should be shown to user as final response
- Pango markup requires `GLib.Markup.escape_text()` BEFORE applying regex replacements
- GtkPaned with `wide_handle=True` provides better drag UX for resizable panels

**Thinking Panel UI Patterns:**
- Tool items are added dynamically to `thinking_content_box` during streaming
- Each tool item has: spinner (in-progress) or icon (complete), bold tool name, dimmed description
- `current_tool_item` tracks the active tool for completion updates
- `complete_current_tool()` replaces spinner with checkmark/error icon
- Clear all tool items at start of each new message with `clear_tool_items()`

**Dockerfile Key Packages:**
```
libgcr-4-dev, libgck-2-dev, libpeas-2-dev, gir1.2-peas-2
pip: meson>=1.7,<1.10
```

**Attachment Access Gotchas:**
- Attachments are in `email.attachments` (Gee.List<Geary.Attachment>)
- Attachment `file` property is a GLib.File - may be null if not saved to disk
- Use `Geary.Memory.FileBuffer` to read attachment content
- Text detection via MIME type: `text/*`, `application/json`, `+xml`, `+json` suffixes
- Base64 encoding for binary attachments, text for text-based types
- Size limits: default 10MB, max 50MB (configurable in `get_attachment_content`)

---
*Last updated: 2026-01-23 (Session 3: Attachment access & sidebar fix)*

## Instructions for user
***The "Let's Pick This Up Again" Prompt***
When to use: Paste this first thing in the morning.

"New session started. Please read the README.md, specifically the 'AI Context & Session State' section.

Based on the Architecture, Tooling, and Next Steps listed there:

Briefly confirm you understand the current stack and architectural patterns.

Check the Environment Variables list and tell me if you need me to provide any values to proceed.

Suggest the best way to tackle the first item in the 'Next Steps' list."

***The Updated "Now Let's Wrap Up" Prompt***
When to use: Use this at the end of every session to "save" the state.

"We are finishing this session. Update the 'AI Context & Session State' section in README.md to reflect our current reality.

Specifically, ensure you update:

Architecture/Tooling changes: Did we add a new library or change a data flow today?

Environment Variables: Did we introduce any new required .env keys?

The State Dump: Move finished 'Next Steps' to 'Recent Accomplishments' and define the roadmap for tomorrow.

Mental Context: Note any 'gotchas' or specific patterns we established today that I should remember next time.

Summarize what you updated, then we are done for the day."
