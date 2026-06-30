# Architecture

## Primary Decision

Build native Mac first:

- SwiftUI app shell
- AppKit `NSTextView` editor
- SQLite local store
- Markdown files in `~/phoenix`
- Swift concurrency for indexing and parsing
- Native file watching
- Menu bar helper for global capture later
- Swift CLI
- No cloud sync in v0
- No model calls in v0

## Package Shape

The project is package-first for reproducible build and test commands.

A future milestone should add an app-bundle Xcode project (or a generated one) when signing, app lifecycle, UI tests, the menu bar helper, and the system-global hotkey require it. See ADR-002.

## Modules

```txt
Daymark
  SwiftUI app shell
  Windows
  Commands
  Settings
  Editor bridge

DaymarkCore
  Workspace model
  Notes
  Blocks
  Tasks
  Slip and capture
  Support (atomic writes, hashing, Markdown fence scanning)
  Rollover planner (pure)
  Dynamic block engine (parser, renderer, patch planner, cache)
  Codex task drafting and parsing

DaymarkStore
  SQLite connection
  Migrations
  Repositories
  FTS index
  Atomic note projection (one transaction per note)
  Event log (planned; declares the event vocabulary only, no table yet)

DaymarkIndexer
  File watcher
  Markdown parser
  Block hashing
  DailyMarkdownProjectionReader (the single daily-Markdown projection path)
  Incremental indexing and rebuild-with-prune
  Rollover execution (TaskRolloverEngine)
  External edit reconciliation

DaymarkAgents
  Source selection (implemented)
  Deterministic Codex draft preview (implemented; no model or prompt calls)
  Approval workflow (implemented for Codex handoff)
  Agent run storage (placeholder; not implemented)

daymark
  CLI commands: see README.md and `daymark help` for the full list.
```

## Data Flow: Typing

```txt
User types
-> editor buffer updates immediately
-> debounced autosave writes Markdown atomically
-> background parser updates blocks/tasks
-> SQLite projection updates atomically (one transaction per note)
-> dependent views refresh
```

Typing must never wait on SQLite, parsing, indexing, AI, network, Calendar, Gmail, or Codex.

## Data Flow: External File Edit

```txt
Codex/Cursor/terminal edits a file in ~/phoenix
-> file watcher sees change
-> indexer reads changed file
-> parser computes content hash and block hashes
-> SQLite projections update
-> open editor reconciles if visible
-> conflict UI appears only if there are unsaved local edits
```

## Data Flow: Codex Task Creation

```txt
User selects text
-> presses Command Shift C
-> Daymark extracts selected text and source note metadata
-> composer generates structured task preview
-> user edits or approves
-> Daymark writes Markdown file in specs/tasks/
```

The source note is not modified by task creation. A backlink-to-Today write is planned and
parked (see `docs/PARKING_LOT.md`); it would be a separate, explicit, approved write.

## SQLite Schema

Implemented today (migrations `001`-`004` plus `schema_migrations`): `notes`, `blocks`,
`notes_fts` (FTS5), `tasks`, `rollovers`.

Planned but not built: `entities`, `block_entities`, `source_items`, `agent_runs`, `events`.
The dynamic block cache is a rebuildable JSON file (`.daymark/dynamic-blocks.json`, ADR-010),
not a SQLite table.

SQLite is an index and projection. Markdown remains the source of truth.
