# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Daymark is

A high-craft, local-first native macOS workspace centered on today's Markdown note. Markdown files in `~/phoenix` are the human-readable source of truth; SQLite at `~/phoenix/.daymark/daymark.db` is a rebuildable local index and projection. The app opens to Today, captures fast, and turns notes into tasks, open loops, dynamic blocks, and Codex-ready specs.

The repo is at the **governance and scaffold** stage. Most modules are intentional placeholders (for example `DaymarkStore/Database.swift` is a stub with no SQLite library wired in yet). The next milestone is Milestone 0, the taste prototype. Check `docs/PROGRESS.md` and `docs/ROADMAP.md` for current state before assuming a feature exists.

## Commands

```bash
swift build                 # build all targets
swift test                  # run the SwiftPM test suite
swift test --filter TaskParserTests          # one test class
swift test --filter DaymarkCoreTests.TaskParserTests/testParsesOpenAndCompletedTasks  # one method
swift run Daymark           # launch the SwiftUI app shell
swift run daymark doctor    # check local scaffold health (workspace dirs, db, index plan)
swift run daymark today     # print sample Today markdown
```

The `scripts/*.sh` wrappers (`build.sh`, `test.sh`, `build_and_run.sh`, `doctor.sh`) just call the commands above.

Build note (observed in this environment): after editing a source file, an incremental `swift test` can fail to relink the `@main` executables (`Undefined symbols: _DaymarkAppShell_main` / `_DaymarkCLI_main`). Run `swift package clean` before `swift test` when that happens. `swift build` links the executables fine; only the test build hits it.

## Package and directory layout

This is a SwiftPM package (`Package.swift`), not an Xcode project. Two source trees, mapped explicitly via `path:` in the manifest:

- `Daymark/`: the SwiftUI app shell (target `DaymarkAppShell`, product executable named `Daymark`). Uses an Xcode-style folder layout (`App/`, `Editor/`, `UI/`).
- `Sources/`: the shared libraries and the CLI.
- `Tests/`: the actual test targets run by `swift test`.
- `DaymarkTests/` and `DaymarkUITests/` at the repo root are **placeholders** for a future Xcode app-test layout. They are not referenced by `Package.swift` and do not run under `swift test`. Real tests go in `Tests/`.

Two executables: `Daymark` (app shell) and `daymark` (CLI, source in `Sources/daymark`).

## Module boundaries (enforce the dependency direction)

```
DaymarkCore      no dependencies. Domain model: Notes, Blocks, Tasks, DynamicBlocks, CodexTasks, Workspace
DaymarkStore     depends on Core. SQLite connection, Migrations, Repositories, FTS, EventLog
DaymarkIndexer   depends on Core + Store. FileWatcher, MarkdownParser, BlockHasher, WorkspaceIndexer
DaymarkAgents    depends on Core. SourceSelector, PreviewBuilder, AgentRunStore
DaymarkAppShell  depends on all four libraries
DaymarkCLI       depends on all four libraries
```

Keep `DaymarkCore` dependency-free. Do not introduce upward or sideways dependencies between libraries (for example Store must not import Indexer).

## Architecture invariants

These are non-negotiable design rules, documented in `docs/ARCHITECTURE.md` and `docs/DECISIONS.md`:

- **Markdown is the source of truth, SQLite is a projection.** Files in `~/phoenix` win; the database is rebuildable. Reconcile divergence with content hashes, atomic writes, and file watching, never by treating the DB as authoritative.
- **Typing must never block.** The editor buffer updates immediately; autosave, parsing, indexing, SQLite, AI, network, Calendar, Gmail, and Codex all run after the keystroke, never in its path. See `docs/PERFORMANCE_BUDGETS.md`.
- **External edits flow through the watcher.** Codex/terminal/Cursor edits to `~/phoenix` are picked up by the file watcher, re-parsed, and reconciled; conflict UI appears only when there are unsaved local edits.
- **Every external action requires preview and approval** (Codex task files, future Gmail drafts). Nothing sends or writes outside the workspace silently.
- Editor is AppKit `NSTextView` wrapped for SwiftUI (ADR-001); the shell is SwiftUI. Do not replace with `TextEditor`, Tauri, Electron, or a web editor.

## Governance (this repo is doctrine-driven)

`AGENTS.md` is the operating contract. Before product or architecture changes, read the mandatory context files it lists: `docs/PRODUCT_SPEC.md`, `docs/ROADMAP.md`, `docs/QUALITY_BAR.md`, `docs/ARCHITECTURE.md`, `docs/NON_GOALS.md`, `docs/ACCEPTANCE_CRITERIA.md`. For UI/motion/interaction work also read `docs/DESIGN_SYSTEM.md`, `docs/INTERACTION_SPEC.md`, `reference/mockups/`, and `reference/cold-start-craft/`.

Scope control rules:

- Work on exactly one active milestone per session (current state in `docs/PROGRESS.md`).
- Do not add product surfaces, integrations, dependencies, or architectural patterns unless the task asks for them. Record any such decision as an ADR in `docs/DECISIONS.md`.
- Useful-but-out-of-scope ideas go in `docs/PARKING_LOT.md`, not into code.
- Append a dated entry to `docs/PROGRESS.md` at the end of substantive work.

## Conventions

- Tests currently use **XCTest** (for example `Tests/DaymarkCoreTests/TaskParserTests.swift`). Match the existing style when adding to a test target. Add tests for markdown parsing, task parsing, rollover idempotency, SQLite migrations, file watcher behavior, and Codex task file generation.
- Shared concurrency state uses `actor` (for example `Database`); model types crossing module boundaries are `public`, `Sendable`, and usually `Equatable`.
- UI design lives in `Daymark/UI/DesignSystem/DesignTokens.swift`: light-mode default, warm off-white canvas, 8px card radius / 12px panel radius, fast easeOut motion (80–160ms). No red badges, AI sparkle motifs, chatbot bubbles, or decorative animation on command palette / capture.
- The default workspace root is `~/phoenix` (`WorkspaceRoot.defaultWorkspace`); the index lives in `~/phoenix/.daymark/`.
