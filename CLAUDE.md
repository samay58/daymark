# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Daymark is

A high-craft, local-first native macOS workspace centered on today's Markdown note. Markdown files in `~/phoenix` are the human-readable source of truth; SQLite at `~/phoenix/.daymark/daymark.db` is a rebuildable local index and projection. The app opens to Today, captures fast, and turns notes into tasks, open loops, approval-gated dynamic blocks, Codex-ready specs, and previewed meeting prep exports.

The repo has a working local substrate: an AppKit-backed editor, file watcher, FTS search, settings, a `Database` actor over the system SQLite3 C API (no third-party SQLite dependency), migrations, repositories, and an event log. Beyond that substrate, many product surfaces are still placeholders.

**This paragraph cannot tell you the current state, so do not trust it for that.** The active milestone, what is done, and what is in progress live in `docs/PROGRESS.md` (read the `## WHERE WE LEFT OFF` block at the end) and `docs/ROADMAP.md`. Read those first, and verify a feature actually exists in the code before assuming it.

## Commands

```bash
swift build                 # build all targets
swift test                  # run the SwiftPM test suite
swift test --filter TaskParserTests          # one test class
swift test --filter DaymarkCoreTests.TaskParserTests/testParsesOpenAndCompletedTasks  # one method
swift run Daymark           # launch the SwiftUI app shell
swift run daymark doctor    # read-only workspace + index health check
swift run daymark today     # print today's note from disk (or the template it would use)
swift run daymark init      # create workspace dirs and today's note (additive only)
swift run daymark index     # project today's note into the index database
swift run daymark rebuild   # rebuild the index from every daily Markdown file
swift run daymark capture <text>   # append to this month's slip (or --today / --task)
swift run daymark rollover  # roll open prior tasks into Today's Brief (--apply to write)
swift run daymark end-of-day       # list today's still-open tasks
swift run daymark open-loops       # list open tasks grouped into buckets (read-only)
swift run daymark codex-task --source <path> --line <n>  # preview a Codex task draft (or --selection-file <path>; --apply writes under specs/tasks/)
swift run daymark context-bundle --task specs/tasks/<file>.md  # preview a context bundle from a task file (--apply writes under artifacts/context-bundles/)
swift run daymark blocks refresh --source <path>   # preview /daymark open-loops, source-list, codex-context, or weekly-review output (--apply writes one idempotent region + .daymark/dynamic-blocks.json)
swift run daymark meeting-prep --event-file /tmp/event.json  # preview local meeting prep Markdown (--apply writes one file under meetings/)
swift run daymark search <q>       # full-text search the index
```

CLI subcommands live in `Sources/daymark/DaymarkCLI.swift`; run `swift run daymark` with no args for the full list. Every command accepts `--root <path>` (or reads `DAYMARK_WORKSPACE_ROOT`) to target a workspace other than `~/phoenix`; this is how the temp-workspace verification checks in `docs/PROGRESS.md` run against a scratch directory. CLI behavior is covered by seven `*CommandTests` classes in `Tests/DaymarkCLITests/` (capture, codex-task, dynamic-blocks, end-of-day, meeting-prep, open-loops, rollover), not one per subcommand.

In-app Dynamic Blocks refresh routes through `DynamicBlockRefreshService`, the same planner path used by the CLI. The app previews from the current editor buffer, disables stale applies if the buffer changes, and writes only on approval: a card's Apply writes that card's patch alone, and new `/daymark` lines get an anchored Insert/Cancel popover that writes nothing until Insert.

The `scripts/*.sh` wrappers (`build.sh`, `test.sh`, `build_and_run.sh`, `doctor.sh`, `run_app.sh`) call the commands above with the toolchain pinned by `scripts/toolchain.sh`. `scripts/test.sh` runs the full canonical test flow. `scripts/install_app.sh` builds a release `Daymark.app` and replaces `/Applications/Daymark.app`, the ad hoc-signed daily-use build ADR-002 allows.

Build note (observed in this environment): after editing a source file, an incremental `swift test` can fail to relink the `@main` executables (`Undefined symbols: _DaymarkAppShell_main` / `_DaymarkCLI_main`). Run `swift package clean` before `swift test` when that happens. `swift build` links the executables fine; only the test build hits it.

Toolchain note (observed 2026-07-05): `xcode-select` on this machine points at CommandLineTools, which fails to compile `Package.swift` itself. Run every swift command with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. That toolchain (Swift 6.4) defaults to the new `swiftbuild` build system, which fails on this package with an xcbuild "unable to open dependencies file" error; add `--build-system native` to every `swift build` / `swift test` invocation until the default backend is fixed. That flag now emits a deprecation warning on every invocation ("has been deprecated and will be removed in a future release"), but it still works and stays required until the default backend is re-tested against this package.

CLI test harness: the `DaymarkCLITests` classes (all named `*CommandTests`) do not link the CLI target. They launch the prebuilt `.build/.../daymark` binary as a subprocess, and `DaymarkCLITests` declares no SwiftPM dependency on `DaymarkCLI`. So `swift test --filter SomeCommandTests` does not rebuild `daymark` first and runs against a stale or missing binary. The canonical flow (mirrored in `docs/PROGRESS.md` "Required Checks") is: run the library suite with `swift test --skip CommandTests`, then for the CLI tests `swift build --product daymark` followed by `xcrun xctest .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest` (optionally scoped with `-XCTest DaymarkCLITests.CodexTaskCommandTests,...`).

## Package and directory layout

This is a SwiftPM package (`Package.swift`), not an Xcode project. Two source trees, mapped explicitly via `path:` in the manifest:

- `Daymark/`: the SwiftUI app shell (target `DaymarkAppShell`, product executable named `Daymark`). Uses an Xcode-style folder layout (`App/`, `Editor/`, `UI/`).
- `Sources/`: the shared libraries and the CLI.
- `Tests/`: the actual test targets run by `swift test`.

Two executables: `Daymark` (app shell) and `daymark` (CLI, source in `Sources/daymark`).

## Module boundaries (enforce the dependency direction)

```
DaymarkCore      no dependencies. Domain model + readable-Markdown stores: Notes, Blocks, Tasks, DynamicBlocks, CodexTasks, Workspace, Slip (capture), Support (AtomicFileWriter, ContentHasher), NoteTokens (checkbox, tag, link, and due-date scanning that powers the live editor and card rendering)
DaymarkStore     depends on Core. SQLite connection, Migrations, Repositories, FTS, EventLog
DaymarkIndexer   depends on Core + Store. FileWatcher, MarkdownParser, BlockHasher, WorkspaceIndexer
DaymarkAgents    depends on Core. SourceSelector, PreviewBuilder, AgentRunStore
DaymarkAppShell  depends on all four libraries
DaymarkCLI       depends on Core + Store + Indexer + Agents
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
- UI design lives in `Daymark/UI/DesignSystem/DesignTokens.swift`: light-mode default, warm off-white canvas, 8px card radius / 12px panel radius, fast easeOut motion (80-160ms). No red badges, AI sparkle motifs, chatbot bubbles, or decorative animation on command palette / capture.
- The default workspace root is `~/phoenix` (`WorkspaceRoot.defaultWorkspace`); the index lives in `~/phoenix/.daymark/`.
