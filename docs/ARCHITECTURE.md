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

This scaffold starts package-first for reproducible build and test commands.

Future Milestone 0 work should add an app-bundle Xcode project or generated Xcode project if needed for signing, app lifecycle, UI tests, menu bar helpers, and global hotkeys.

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
  Rollover engine
  Dynamic block engine
  Codex task drafting

DaymarkStore
  SQLite connection
  Migrations
  Repositories
  FTS index
  Event log

DaymarkIndexer
  File watcher
  Markdown parser
  Block hashing
  Incremental indexing
  External edit reconciliation

DaymarkAgents
  Future source selection
  Future prompt assembly
  Preview generation
  Approval workflow
  Agent run storage

daymark
  Future CLI commands
```

## Data Flow: Typing

```txt
User types
-> editor buffer updates immediately
-> debounced autosave writes Markdown atomically
-> event recorded
-> background parser updates blocks/tasks
-> SQLite projections update
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
-> Daymark records event
-> Daymark adds optional backlink to Today if approved
```

## Initial SQLite Schema

The first schema should include notes, blocks, tasks, rollovers, entities, block_entities, dynamic_blocks, source_items, agent_runs, events, and an FTS5 note index.

SQLite is an index and projection. Markdown remains the source of truth.
