
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
docker-compose run --rm build

# Run tests
docker-compose run --rm test

# Create .deb package (output in ./dist/)
docker-compose run --rm package

# Interactive shell for debugging
docker-compose run --rm shell

# Clean build cache
docker-compose run --rm clean
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
- Install with: `sudo apt install --reinstall /tmp/geary-gemini_46.0_amd64.deb`

### Current Blockers

*None - all Gemini UI features implemented and build working!*

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

### Next Steps

1. [ ] Wire up GeminiService to actual button handlers (currently show placeholder notifications)
2. [ ] Add gemini-cli auto-install dialog UI (modal dialog for first-time install)
3. [ ] Test full translate/summarize flow with gemini-cli installed
4. [ ] Add keyboard shortcut for Gemini sidebar toggle
5. [ ] Consider adding Gemini suggestions in email search

### Session Notes

**gemini-cli Integration Notes:**
- gemini-cli installed via: `npm install @google/gemini-cli@latest`
- Run prompts with: `gemini -p "your prompt here"`
- Auth via: `gemini auth login` (opens browser for OAuth)
- App stores local install in `~/.local/share/geary-gemini/node_modules/`

**UI Implementation Details:**
- Translate/Summarize buttons: `ui/components-conversation-actions.ui` lines 81-132
- Composer AI helper: `ui/composer-editor.ui` (GtkRevealer with prompt bar)
- Gemini sidebar toggle: `ui/components-headerbar-conversation.ui` (GtkToggleButton)
- Sidebar container: `ui/application-main-window.ui` (GtkRevealer wrapping GtkBox)
- Actions: `win.translate-conversation`, `win.summarize-conversation`, `win.toggle-gemini-sidebar`, `edt.ai-help`

**New Files Created This Session:**
- `src/client/gemini/gemini-sidebar.vala` - Chat sidebar widget class
- `ui/gemini-sidebar.ui` - Sidebar UI definition with header, chat area, input, status

**Files Modified This Session:**
- `ui/application-main-window.ui` - Added root_box wrapper with sidebar revealer
- `ui/components-headerbar-conversation.ui` - Added Gemini toggle button
- `src/client/application/application-main-window.vala` - Added sidebar GtkChild refs, service init, toggle handler
- `src/client/meson.build` - Added gemini-sidebar.vala
- `ui/org.gnome.Geary.gresource.xml` - Added gemini-sidebar.ui

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

**Dockerfile Key Packages:**
```
libgcr-4-dev, libgck-2-dev, libpeas-2-dev, gir1.2-peas-2
pip: meson>=1.7,<1.10
```

---
*Last updated: 2026-01-18*

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
