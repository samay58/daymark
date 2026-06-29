# Progress Log

## 2026-06-28

### Active Milestone

Governance and scaffold.

### Goal

Create repository guidance, product docs, module boundaries, and a compileable Swift scaffold before product features begin.

### Completed

- Created `AGENTS.md`.
- Created required governance docs.
- Saved Daymark product mockups under `reference/mockups/`.
- Saved Cold Start craft references under `reference/cold-start-craft/`.
- Created Swift package with app shell, local modules, CLI stub, scripts, and starter tests.

### Acceptance Criteria Status

- Governance docs exist: pass.
- Product mockups saved: pass.
- Craft references saved: pass.
- Swift package builds: pass.
- Starter tests pass: pass.
- CLI doctor stub runs: pass.

### Tests/Checks Run

- `swift build`
- `swift test`
- `swift run daymark doctor`

### Deviations

- Started package-first instead of creating an Xcode project. Recorded in `docs/DECISIONS.md`.
- Resolved card radius to 8 px default and 12 px maximum to align with global design guidance while preserving Daymark softness.

### Next Step

Run build and tests. Then begin Milestone 0: Taste prototype.

## 2026-06-28 (Milestone 0 taste pass)

### Active Milestone

Milestone 0: Taste Prototype.

### Goal

Turn the compiling scaffold into a stronger taste prototype with fake data only, so we can judge whether Daymark feels native, quiet, fast, and worth leaving open all day. No product functionality.

### What Changed

- Aligned the design tokens with `docs/DESIGN_SYSTEM.md`. Added `textTertiary`, `warning`, `success`, a hex color initializer, layout metrics, a `DesignType` typography scale, and motion constants tuned to the interaction spec (slip 90 ms, palette open 90 ms, checkbox spring 120 ms, popover 140 ms, panel 180 ms).
- Migrated `AppState` from `ObservableObject` to the `@Observable` macro, with `@State` ownership in `DaymarkApp` and `@Environment` reads in the views. This matches the modern Swift observation model and gives fine-grained view updates, which serves the "typing must stay instant" principle.
- Rebuilt the sidebar to match the mockups: native material, Daymark wordmark, default/selected/hover row states, an Open Loops count, a divider into Archive/Tags/Settings, and a "Stored locally / ~/phoenix" footer card with selection wired to `AppState`.
- Replaced the plain editor surface with a styled document renderer for Today (the roadmap's "Today editor mock"). A small prototype Markdown reader (`DocumentParser`) renders sage `##` section markers, bullets, task checkboxes with strikethrough, a blockquote with a sage rule and attribution, wiki links, and a tag chip row. The live date and weekday render from the system clock.
- Added a top bar (back/forward, `~/phoenix` breadcrumb, compose, search, panel toggle) and a status bar (word count, "Edited just now").
- Reworked the right context margin into previewable context and action, not chat: a suggestion card (lightbulb prompt with Preview/Dismiss) and a Codex Task composer card (Title, Goal, Source, Acceptance Criteria checklist, File, with Create Task File / Edit / Cancel). The margin is toggleable and hairline-separated.
- Polished Slip into a right-edge capture panel (header, subtitle, focused capture field, footer actions, "saves" hint) and the command palette into a focused, filterable, keyboard-navigable surface with an ACTIONS group and shortcut hints.
- Improved the AppKit `NSTextView` editor typography (font, line spacing, insets, accent caret, typing attributes). It is kept as the Milestone 1 live-editing surface per ADR-001.
- Pinned the prototype to light appearance and set the default window to 1120x760.

### Acceptance Criteria Status

- `swift build` succeeds: pass.
- `swift test` succeeds: pass (4 tests).
- UI visibly closer to the saved mockups: pass.
- Today remains the center of gravity: pass.
- Slip and command palette present as mocked surfaces: pass.
- Right margin holds previewable context and action, not chat: pass.
- No real persistence, AI, Gmail, Calendar, cloud, or indexing added: pass.

### Tests/Checks Run

- `swift build`
- `swift test`

### Remaining

- Live in-editor Markdown rendering in the AppKit editor (Milestone 1). The styled document is currently a read-only mock.
- Real dark-mode token set. Light appearance is pinned for now.
- Source chip hover-to-popover expansion and the agenda card from the mockups were left out to keep the margin restrained.
- Tests for `DocumentParser` are deferred because it lives in the app target; the real parser in `DaymarkIndexer` is already covered.

### Deviations

- The Today surface renders a styled document mock rather than driving the AppKit editor. This matches the roadmap's "Today editor mock" for Milestone 0 and does not reverse ADR-001; the AppKit editor remains the Milestone 1 editing surface. No new ADR needed.
- No new dependencies or product surfaces were added.

## 2026-06-28 (Milestone 1, local workspace substrate)

### Current Milestone

Milestone 1: make Daymark usable as a real local daily note app, with Markdown as the source of truth and SQLite as a rebuildable projection. No AI, connectors, rollover, or dynamic blocks.

### What Changed

- Workspace resolution: `WorkspaceRoot.resolve(override:environment:)` with precedence explicit override, then `DAYMARK_WORKSPACE_ROOT`, then the `~/phoenix` default. Added tilde expansion and `expandedURL`.
- Workspace bootstrap: `WorkspaceBootstrapper` creates the documented directories (daily, slip, inbox, projects, deals, people, meetings, specs/tasks, artifacts subdirectories, .daymark subdirectories). Idempotent and additive; it never removes or overwrites existing files.
- Daily note: `DailyNote.relativePath` is `daily/YYYY/MM/YYYY-MM-DD.md`, with a readable default template (H1 title, Brief, Capture, Decisions, End of day). `DailyNoteStore` ensures today's note without overwriting an existing one, loads it, and saves atomically.
- Atomic writes: `AtomicFileWriter` writes through a temp file and replaces in place, creating parent directories first.
- Stable hashing: `ContentHasher` (SHA-256) replaces `String.hashValue` for reconciliation, so a hash is reproducible across processes. `BlockHasher` now delegates to it.
- SQLite projection: the `Database` actor opens with WAL and foreign keys, applies migrations in a transaction, and upserts notes and blocks by workspace-relative path (reprojecting replaces blocks, never appends). `NoteRepository.projectNote` is the projection facade.
- Indexer: `WorkspaceIndexer` reads a daily Markdown file, parses blocks, derives the title via `MarkdownParser.title`, and projects it. `indexToday` projects today; `rebuild` reprojects every file under `daily/`, proving the index is a function of the Markdown. Title comes from the shared parser so the projection and the search index agree.
- CLI: `daymark doctor` is read-only (reports directories, today's note, daily file count, database presence, and declared migrations without creating anything). `init`, `index`, and `rebuild` are the mutating paths; `today` prints the note or its template. All honor `--root` and `DAYMARK_WORKSPACE_ROOT`. Fixed the async `@main` so the CLI exits cleanly.
- App launch: `AppState.prepareWorkspace` resolves the root, bootstraps, ensures today's note, and loads it into the editor off the main actor on launch. `handleTodayTextChange` debounces an atomic Markdown save. The app writes Markdown only; indexing stays in the CLI for this milestone.

### Acceptance Criteria Status

- App resolves a workspace root and can open Today: pass (CLI and app launch flow; the app side is verified by build, not yet by driving the read-only mock).
- Workspace directories created if missing: pass.
- Today's daily note created if missing and never overwritten: pass.
- Autosave with atomic writes, Markdown stays human-readable: pass (writer and store covered by tests; app autosave path wired, see remaining).
- SQLite is an index and projection, not the source of truth: pass.
- First migrations for notes and blocks: pass.
- Index and database rebuildable from Markdown: pass (the rebuild test reconstructs the projection after deleting the database file).
- Doctor reports health without mutating: pass.

### Tests/Checks Run

- `swift build`
- `swift test` (43 tests, 0 failures)
- End to end CLI against a temporary workspace root (never `~/phoenix`): doctor before init creates nothing, init creates 13 directories and today's note, doctor after init shows the database still absent, index projects 1 note and 10 blocks, rebuild from two daily files projects 2 notes and 14 blocks, today prints the note.

### Remaining in Milestone 1

- The Today surface still renders the read-only document mock, so the app autosave path is wired but not yet exercised by typing. Swapping `DocumentView` for the editable `NSTextViewRepresentable` activates it. This is the main open M1 slice.
- The app does not yet update the SQLite index on save; indexing is CLI only for now by design.
- File watcher and external-edit reconciliation are not started.

### Concurrency Note

A separate session worked the Store layer in parallel during this slice, adding a search migration (`002_note_search.sql`), full-text search, `SearchTests`, and a `MarkdownParser.title` helper. That work is additive and the combined tree builds and tests green. This repo is not under git, so the two threads share a working tree with no safety net. Recommend initializing git or assigning one owner per file before the next parallel session.

### Deviations

- App launch bootstraps and creates today's note against the resolved root. With the default `~/phoenix`, that would scatter Daymark directories into the existing vault. This session never ran a mutating command against `~/phoenix`; all verification used temporary roots. The vault coexistence decision (dedicated Daymark workspace vs living inside `~/phoenix`) is parked for the user to ratify before first real launch.
- Introduced a live SQLite connection using the system `libsqlite3` via `import SQLite3`, no external package. Recorded as ADR-004.

## 2026-06-28 (Milestone 1 completion: live editor, watcher, search, settings)

### Current Milestone

Milestone 1: Local Workspace. This slice completes the items the substrate session deferred, so the app is usable as a real daily note app for a full day.

### Context

Two parallel sessions built the M1 substrate: one added the workspace, daily note, atomic writes, SQLite notes and blocks, indexer, and CLI; the other added FTS search to the store. This session took over the single working tree after confirming the other writers had stopped, integrated both halves, and finished the deferred slices.

### What Changed

- Live editing: Today now renders the editable AppKit `NSTextViewRepresentable` instead of the read-only document mock. Typing updates the buffer immediately; a `MarkdownHighlighter` applies calm syntax styling (headings, task checkboxes with completed strikethrough, bullets, blockquotes, inline code, wiki links, bold, italic) by setting display attributes only, so the bytes on disk stay literal Markdown. Removed the superseded `DocumentView`, `DocumentParser`, and the no-op `MarkdownRenderer`.
- Autosave plus projection: `AppState` debounces an atomic save 800 ms after the last keystroke, off the keystroke path, then reprojects today into SQLite so search reflects the latest text.
- Background index on launch: `prepareWorkspace` loads today's text first so Today is editable immediately, then opens the database, migrates, indexes today, and starts the watcher in the background.
- File watcher: `FileWatcher` is now a real FSEvents recursive watcher. External edits in the daily folder reproject into the index, and changes to today's note reconcile into the editor. With no unsaved local edits the disk version is adopted; with unsaved edits a conflict banner offers keep mine or use disk version. A content guard against the app's own writes prevents echo loops.
- Local search: FTS5 migration `002_note_search.sql`, `Database.search` with tokenized prefix queries, `NoteRepository.search`, and `Database.deleteNote` so removed files leave the index. Surfaced as a live Notes section in the command palette and as `daymark search` in the CLI.
- Settings: a real workspace root field with a folder picker, reveal in Finder, and live apply. The root persists in `UserDefaults` through `SettingsStore`, and `changeWorkspaceRoot` tears down the index and watcher before reloading Today from the new location.

### Acceptance Criteria Status

- Today note persists as Markdown: pass.
- External edits from terminal or Codex appear: pass (FSEvents watcher reconciles today's note; watcher covered by tests).
- Search works locally: pass (FTS covered by tests; demonstrated end to end through the CLI).
- No network required: pass.
- No data loss: pass (atomic writes plus the unsaved-edit conflict guard).
- Today opens before indexing completes: pass (text loads first, indexing runs after).
- Typing never waits on SQLite or indexing: pass (autosave debounced off the keystroke; projection on the database actor).
- SQLite rebuildable from files: pass (rebuild test and CLI rebuild).

### Tests/Checks Run

- `swift build`.
- `swift test` (45 tests, 0 failures), including FTS search tests, file to projection indexer tests, and FSEvents file watcher tests.
- End to end CLI against a temporary workspace (never `~/phoenix`): init creates the workspace and today's note, index projects it, an external edit then rebuild reprojects, search returns the right note for exact and prefix queries and nothing for a miss, doctor reports health.
- The app builds and launches without crashing. The live editor could not be confirmed by screenshot in this environment (single Space, terminal frontmost); behavior is verified through the tests and CLI.

### Remaining

- A signed app bundle, global hotkey, and menu bar helper stay deferred (Milestone 2 and ADR-002). `scripts/run_app.sh` wraps the binary for local viewing only.
- Vault coexistence resolved: the default workspace is now a dedicated `~/Daymark` folder (ADR-005), so the existing `~/phoenix` vault stays untouched. Settings and `DAYMARK_WORKSPACE_ROOT` still override it.

### Deviations

- The Today surface moved from the read-only mock to the live AppKit editor. This realizes ADR-001 rather than reversing it, so no new ADR.
- The file watcher uses FSEvents from CoreServices, a system framework, so no new dependency and no ADR.
- The working tree is still not under git. This session took sole ownership to avoid clobbering the parallel writers (see PARKING_LOT).

## 2026-06-28 (Milestone 1 acceptance audit and close)

### Current Milestone

Milestone 1: Local Workspace, acceptance audit and hardening. No new product capability.

### Verified with real data (temporary workspace, never the real home)

- Default root resolves to `~/Daymark` (ADR-005); `daymark doctor` against it is read-only and creates nothing.
- Bootstrap creates only the documented top-level entries (.daymark, artifacts, daily, deals, inbox, meetings, people, projects, slip, specs) and nothing extra.
- Today's note path is `daily/YYYY/MM/YYYY-MM-DD.md`, created if missing with readable Markdown.
- Reopening (init twice) does not overwrite an edited note.
- An external edit stays readable and is picked up by `rebuild` and `search`.
- SQLite lives under `.daymark` and is rebuildable: deleting `daymark.db` and rebuilding reconstructs the projection from Markdown.
- The app still opens to Today.

### What changed (hardening only)

- Extracted a read-only `WorkspaceHealth` model in `DaymarkStore` and made `daymark doctor` format it, so doctor health is now unit-tested (empty workspace, after bootstrap, database presence) instead of only manually observed. Removed the now-dead CLI helpers.
- Added `MarkdownParser` tests on a realistic daily note (the PRODUCT_SPEC shape): title from the first heading, fallback to the first non-empty line, default-template title, and verbatim preservation of a task line with tags and metadata.
- Aligned PRODUCT_SPEC and CLAUDE.md to the `~/Daymark` default (ADR-005). PRODUCT_SPEC previously stated `~/phoenix` as the default, which contradicted the implementation. Remaining `~/phoenix` mentions in ARCHITECTURE, AGENTS, ROADMAP, ACCEPTANCE_CRITERIA, DESIGN_SYSTEM, and INTERACTION_SPEC are illustrative and covered by ADR-005's note; a full sweep is optional later.
- Confirmed the earlier title-extraction duplication is already consolidated (`WorkspaceIndexer` uses `MarkdownParser.title`; no `firstHeading`).

### Acceptance Criteria Status (all pass)

- `swift build` passes.
- `swift test` passes (52 tests, up from 45).
- `daymark doctor` reports real workspace health.
- A temporary workspace bootstraps safely.
- Today's note creates and reopens without overwrite.
- Markdown readable outside the app.
- SQLite under `.daymark` and rebuildable.
- Tests cover the local workspace invariants (root resolution, tilde expansion, bootstrap directory list, daily path, create-if-missing, no-overwrite, atomic write, migrations, doctor health, parser on a real note).
- App still centers Today.
- No later-milestone features added.

### Tests/Checks Run

- `swift build`.
- `swift test` (52 tests, 0 failures).
- `daymark doctor` against the default root (read-only, nothing created).
- Real-data CLI pass against a temporary workspace: documented dirs, today path, no-overwrite, external edit, search, delete-db-and-rebuild.

### Milestone 1 status: READY TO CLOSE

The local Markdown loop is trustworthy. Files are the source of truth, SQLite is a rebuildable projection, typing does not wait on the database, and nothing requires the network.

### Next session: Milestone 2, Slip and Capture

Build the global capture path per ROADMAP (global hotkey, menu bar helper, floating Slip panel, temporary captures, append to Today, discard, promote to task). Do not start until asked.

### Known follow-ups (not blockers)

- Initialize git for the repo (top PARKING_LOT item); the tree is still unversioned and was the source of the parallel-writer collision.
- The live editor stays screenshot-unverified in this environment; behavior is covered by tests and the CLI.
- Optional: sweep illustrative `~/phoenix` mentions in the remaining docs to `~/Daymark`.

### Deviations

- No new ADR. PRODUCT_SPEC and CLAUDE.md were aligned to the existing ADR-005 default.

## 2026-06-28 (Codex stocktake after Claude Code passes)

### Current Status

Milestone 1 remains ready to close. The repo is on track for Milestone 2: Slip and Capture.

### Verified from Current Tree

- `swift build` passes.
- `swift test` passes: 52 tests, 0 failures.
- `swift run daymark doctor` reports the dedicated `~/Daymark` workspace, today's note, the local `.daymark/daymark.db`, and both declared migrations.
- `docs/PROGRESS.md` shows Milestone 0 completed, Milestone 1 implemented, and Milestone 1 acceptance-audited.
- `docs/DECISIONS.md` includes ADR-005, which moves the default workspace from `~/phoenix` to `~/Daymark` to avoid scattering Daymark directories into the existing Phoenix vault.

### Assessment

Daymark has a credible local-first substrate:

- Markdown is still the source of truth.
- SQLite is a rebuildable projection.
- Today is the center of the app.
- Local search, file watching, autosave, settings, and doctor health are in place.
- No AI, Gmail, Calendar, cloud sync, embeddings, or dynamic blocks have leaked into the milestone.

### Gaps Before More Parallel Work

- The repo is still not under git. Initialize version control before starting Milestone 2.
- The live editor remains screenshot-unverified in this environment, although the behavior is covered by build, tests, CLI checks, and app launch.
- Remaining illustrative `~/phoenix` mentions in docs are not blockers because ADR-005 defines `~/Daymark` as the default.

### Next Recommended Task

Start Milestone 2: Slip and Capture.

Build the fastest local capture path without weakening the local file guarantees:

- real global hotkey or the smallest app-bundle step needed to support it
- menu bar/helper decision if required
- floating Slip panel
- temporary captures
- append to Today
- discard
- promote to task as a Markdown line only
- tests around capture storage and append behavior

## 2026-06-28 (Default workspace reverted to ~/phoenix, git initialized)

### What Changed

- Reversed ADR-005. The default workspace root is `~/phoenix` again (`WorkspaceRoot.defaultWorkspace`), because operating directly on the vault is the point of the product. Earlier doc and stocktake entries that say the default is `~/Daymark` are superseded by this. Bootstrap stays additive: it only adds Daymark directories it does not already find and never removes or overwrites existing vault content. Overrides (`DAYMARK_WORKSPACE_ROOT`, Settings) are unchanged.
- Reverted the `~/Daymark` references in code (`WorkspaceRoot`, CLI usage, Settings placeholder), the default-resolution test, and the docs (PRODUCT_SPEC, CLAUDE.md, PARKING_LOT). DECISIONS.md marks ADR-005 as reversed and keeps the history.
- Initialized git for the repo with a `.gitignore` for build artifacts and an initial commit, so future parallel sessions have version control instead of a shared unversioned tree.

### Tests/Checks Run

- `swift build`.
- `swift test` (52 tests, 0 failures).
- `daymark doctor` resolves `~/phoenix` and is read-only.

### Status

Milestone 1 stays ready to close. Default is `~/phoenix`. Next session: Milestone 2, Slip and Capture (not started).

## 2026-06-28 (Milestone 2: Slip and Capture implemented)

### What Changed

Capture from inside Daymark is real, and there is a scriptable capture-from-anywhere path. This slice was built jointly: the DaymarkCore capture foundation and its tests on one track, the CLI command layer and Slip panel wiring on a parallel Codex companion bound to the same session, converging on the same APIs.

- New `DaymarkCore/Slip/` module:
  - `MarkdownSection.appendingEntry(_:under:to:)` appends a block under a named heading without duplicating the heading and without disturbing other sections. It is a pure string function, so the same logic runs on the in-memory editor buffer and on files.
  - `CaptureFormatter` formats captures as readable Markdown: timestamped bullets (`- HH:mm text`), day headings (`## YYYY-MM-DD`), and open task lines (`- [ ] text`), with multiline captures kept as one item via indented continuations.
  - `SlipStore` appends captures to the monthly file `slip/YYYY-MM.md` (titled `# Slip <Month Year>`, grouped by day heading). Writes are atomic. Blank captures throw `CaptureError.empty` and write nothing.
- `DailyNoteStore` gained `appendCapture` and `appendTask`, which append under today's `## Capture` section, creating the note from the template first when missing and preserving existing content.
- `AppState` gained `saveCapture`, `appendCaptureToToday`, and `promoteCaptureToTask`. Slip-file saves run off the main actor. Today-targeting captures transform the in-memory buffer and persist through the existing debounced autosave and self-write-hash machinery, so typing never waits on capture and the buffer stays consistent with disk.
- `CaptureTextView` is an AppKit-backed capture field (consistent with ADR-001). Return saves to Slip, Shift+Return inserts a newline, Command+Return appends to Today, Command+Shift+T promotes to a task, and Escape cancels. `SlipPanelView` is wired to these actions and the placeholder copy stays plain (`Capture to Daymark`).
- `daymark capture` CLI: appends to the monthly Slip file by default, `--today` appends under today's `## Capture`, `--task` writes an open task line, and text can be piped on stdin. Unknown flags, conflicting `--today/--task`, and missing text fail with a clear message and usage. Capture does no database work, so it is fast and the index stays rebuildable from files.
- New `DaymarkCLITests` target runs the built binary against temporary workspaces end to end.

### Why It Moves Toward The Spec

Capture from anywhere is the Milestone 2 goal. In-app Slip now captures to readable Markdown without blocking Today, and the CLI gives a scriptable capture path that can be bound to a system shortcut today. Markdown stays the source of truth: every capture is a plain-text Markdown write, SQLite is never on the capture path, and the index stays a rebuildable projection of the files.

### Tests/Checks Run

- `swift build`: clean.
- `swift test`: 86 tests, 0 failures (after `swift package clean`, per the known relink note).
- `daymark doctor`: read-only, works on the default `~/phoenix` and on a temp workspace.
- Manual `daymark capture` against a temporary workspace only: slip save, `--today`, `--task`, multiline via stdin, and the empty-capture failure that writes nothing. The real `~/phoenix` was never written during testing.

### Acceptance Criteria

Met: git baseline clean; build, test, and doctor pass; in-app Slip captures without blocking Today; capture to a readable monthly Slip file, to today's `## Capture`, and as a task line; discard and empty captures write nothing; tests use temp workspaces only; no out-of-scope surfaces added.

### Global Hotkey / App-Bundle Decision

Not done in this slice, by design. A true system-global Option+Space (capture when Daymark is not frontmost) needs a signed app bundle and accessibility or Carbon hotkey registration, which is more than this slice should take on. In-app Option+Space already opens Slip when the app is focused (menu shortcut), and the `daymark capture` CLI is the capture-from-anywhere step for now (bindable via Shortcuts, Raycast, or a key remapper). The real global hotkey should be its own Milestone 2 slice, gated by an app-bundle ADR before implementation. No ADR was added because no app-bundle work was done.

### Deviations

A Codex companion bound to this session worked the same files in parallel. The two tracks converged compatibly on the same APIs. At the contention point the user chose to let Codex finish the implementation while this track verified and documented. For future sessions, prefer a single owner per file or per-worktree branches to avoid clobbering.

## WHERE WE LEFT OFF

### Active Milestone

Milestone 2: Slip and Capture. In-app and CLI capture are implemented and green. The open question is the global hotkey.

### Start Here Next

1. Decide the global hotkey path: write an app-bundle ADR and implement system-global Option+Space as its own slice, or accept the `daymark capture` CLI as the capture-from-anywhere mechanism and close Milestone 2.
2. Optional polish: review the Slip panel copy for any remaining non-plain phrasing.
3. When ready, move toward the next milestone.

### Current Truths

- Milestone 0 is complete.
- Milestone 1 is complete and ready to close.
- Milestone 2 capture is implemented: monthly Slip file, append to Today, promote to task, discard, and a `daymark capture` CLI. 86 tests pass.
- Capture writes only Markdown. SQLite is never on the capture path and stays a rebuildable projection.
- The default workspace root is `~/phoenix`; ADR-005 is reversed.
- The true system-global hotkey and any menu-bar or app-bundle work are not built and need an ADR first.
- Do not add Gmail, Calendar, AI, cloud sync, embeddings, task rollover, Open Loops, dynamic blocks, or Codex execution.

### Required Checks

- `git status --short`
- `swift package clean && swift test`
- `swift build`
- `swift run daymark doctor`
