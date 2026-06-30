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

## 2026-06-28 (Milestone 2 hardening: data-safety review)

Two independent adversarial reviews of the capture paths (core logic and app wiring) found real data-safety bugs, since fixed and covered by tests. 95 tests, 0 failures.

### Bugs fixed

- Critical: capturing to Today (or editing) before the real note finished loading could write the SampleData placeholder over the real daily note, silently. The persistence gate was on `hasLoaded`, which is set before the load completes. Split out `didLoadToday`; persistence and Today captures gate on it, and a pre-load Today capture is routed to the Slip file so nothing is lost or clobbered.
- Critical: `SlipStore.save` read the existing month with `try?`, so an unreadable file (bad UTF-8, I/O error) silently became a fresh document and overwrote a month of captures. It now reads with `try` and only starts fresh when the file is genuinely absent or empty.
- High: `MarkdownSection` treated `#` lines inside fenced code blocks as headings, corrupting a code block in the Capture section or matching a `## Capture` that lived only inside a fence. Heading detection now skips fenced regions.
- High: CRLF documents were not matched (a trailing carriage return defeated the heading comparison), so a duplicate `## Capture` was appended. Input is normalized to LF.
- High: the Slip save (the Return path) swallowed write errors and dismissed the panel, losing the capture silently. The save is now synchronous and returns success; the panel dismisses only on a confirmed write and otherwise stays open with the text intact.
- Medium: no flush on quit left a capture in the autosave debounce window vulnerable to Cmd+Q. A termination observer now flushes any pending Today write synchronously.
- Low: IME composition (CJK, accents) confirmed with Return fired a capture; `keyDown` now defers to the input context while text is marked.

### Checks run

- `swift build`, `swift test` (95 tests, 0 failures), `daymark doctor`, manual `daymark capture` against a temp workspace, and an app launch smoke test (boots clean with the new wiring). The real `~/phoenix` was never written.

### Known limitations (documented in PARKING_LOT, deferred by scope)

- Capture's read-modify-write is not transactional against concurrent external writes.
- Multiline captures normalize per-line indentation.
- The `Daymark` app and `daymark` CLI product names collide on case-insensitive filesystems; resolved by the app-bundle milestone.

## 2026-06-28 (Milestone 2 closed, Milestone 3 first slice: tasks index and read-only Open Loops)

Milestone 2 is closed. The system-global hotkey stays deferred behind a future app-bundle ADR (PARKING_LOT), and the `daymark capture` CLI remains the capture-from-anywhere path. This session opened Milestone 3 with the first safe slice: a hardened task model and parser, a rebuildable tasks projection in SQLite, and a read-only Open Loops query and CLI command. No rollover mutation was written.

### What changed

- Task model: `TaskItem` now carries due metadata and source metadata. A `Due` enum captures `due:today`, `due:tomorrow`, and ISO dates (`due:2026-06-29`) as tokens without resolving them against a calendar. New fields are `due`, `notePath`, `lineNumber`, `originalLine`, and `sectionHeading`, plus a derived `sourceKey` (note path, line, normalized text) for rollover identity later. The init keeps defaults so existing call sites are unaffected.
- Parser: `TaskParser` is fence-aware (checkbox lines inside ``` or ~~~ are ignored), tracks the current ATX section heading, records 1-based line numbers and the verbatim source line, normalizes CRLF, and parses `- [ ]`, `- [x]`, and `- [X]`. Tags, mentions, and due tokens are extracted as metadata but stay in the title, so the line round-trips to the same Markdown. Natural-language dates are not parsed.
- SQLite projection: migration `003_tasks.sql` adds a `tasks` table keyed by note with `source_key`, line, title, status, tags, mentions, due, section heading, and original line. `Database.replaceTasks` mirrors `replaceBlocks`: reprojecting a note replaces its task rows rather than appending, so the table is a rebuildable projection. `Database.openTasks` returns open tasks joined to their note path, ordered by path then line. `NoteRepository.projectNote` and `WorkspaceIndexer` now project tasks alongside blocks, so `daymark index` and `daymark rebuild` populate the table.
- Open Loops: `OpenLoops.grouped(tasks:on:)` is a pure function that excludes completed tasks and sorts open ones into buckets. Dated tasks go to Due today, Overdue, or Upcoming by comparing the ISO date to a reference date; the relative tokens are taken at face value (today to Due today, tomorrow to Upcoming). Undated tasks split into Waiting on others (an `@mention` or a `waiting:` marker) and No date. Each task lands in exactly one bucket and empty buckets are omitted.
- CLI: `daymark open-loops` reads the index, groups open tasks, and prints them scannable with `path:line` source locations. It is read-only: it never writes Markdown or rolls tasks forward. It honors `--root` and `DAYMARK_WORKSPACE_ROOT`.

### Design notes

- Due resolution is token-literal for this slice. A `due:today` written three days ago still reads as Due today, because resolving it against the note's own date is natural-language date logic, which this milestone defers. Overdue and Upcoming buckets were added beyond the three the prompt named so that dated tasks (tomorrow, future, past) are never silently dropped from the output.
- The "Waiting on me", "Rolled repeatedly", and "Codex tasks" buckets from INTERACTION_SPEC are not built; they need rollover state and Codex, which are out of scope here.

### Tests/Checks run

- `swift test --skip CommandTests`: 110 library tests, 0 failures (Core, Store, Indexer).
- CLI tests via the built bundle: 13 tests, 0 failures (10 capture, 3 open-loops). Total 123, 0 failures.
- `swift build --product daymark` and `--product Daymark`: both link cleanly on their own.
- `daymark doctor` against the default `~/phoenix`: read-only, reports `003_tasks.sql` declared, creates nothing.
- Manual end-to-end on a temp workspace (never `~/phoenix`): wrote two daily notes with open and completed tasks, ran `rebuild`, ran `open-loops`. Tasks bucketed correctly across Due today, Overdue, Upcoming, Waiting on others, and No date, and the completed tasks did not appear.

### Verification caveat (build collision)

The `Daymark` app and `daymark` CLI products share one path on the case-insensitive filesystem, so a single `swift test` relinks both and whichever wins corrupts the other. When the app wins, the CLI tests launch the app and time out. The library tests are unaffected. To verify the CLI tests, build `--product daymark` to put the CLI at the shared path, then run the prebuilt test bundle with `xctest` so nothing relinks. This is the known collision tracked in PARKING_LOT; the app-bundle milestone resolves it.

### Remaining in Milestone 3

- Task rollover: carry incomplete tasks from prior daily notes into Today as clean Markdown, preserve the original task, prevent duplicate rollovers, and record rollover events.
- Recurrence and end-of-day review.
- An in-app Open Loops surface (the CLI is the read path for now).
- Note-relative resolution of `due:today` / `due:tomorrow` once rollover re-stamps dates.

## 2026-06-28 (Milestone 3 completion: rollover, end-of-day, app Open Loops)

Milestone 3 is ready to close against `docs/ACCEPTANCE_CRITERIA.md`. Rollover is automatic in the app after Today loads, available from the CLI with `daymark rollover --apply`, and idempotent even after deleting and rebuilding SQLite.

### What changed

- Rollover domain: added `TaskRollover`, `RolloverEntry`, and `RolloverPlan` in `DaymarkCore`. The pure planner filters to open tasks from prior daily notes, excludes completed tasks, ignores tasks already present in Today, and appends readable `Rolled over:` bullets under `## Brief`.
- Rollover dedup scheme: each rolled bullet carries a hidden Markdown marker, `<!-- daymark-rollover:<sha256> -->`, where the hash is derived from the source task key. Today Markdown is the authoritative dedup source, so deleting `.daymark/daymark.db`, rebuilding, and running rollover again adds nothing. ADR-006 records the convention.
- Store record: migration `004_rollovers.sql` adds a `rollovers` table with a unique `(source_key, target_note_path)` constraint. `Database.recordRollover` records app-driven rollovers as audit state, while Markdown remains the source of truth.
- Rollover execution: `TaskRolloverEngine` rebuilds the task projection from Markdown, plans rollover, writes only Today's note when applying, records rollover rows, and reprojects Today. The original source note is never modified.
- CLI: added `daymark rollover [--date yyyy-MM-dd] [--apply]`. It dry-runs by default and writes only with `--apply`. Added `daymark end-of-day [--date yyyy-MM-dd]`, a read-only list of today's still-open tasks.
- App launch: after Today loads and the index opens, Daymark runs rollover off the initial load path. If the user has unsaved local edits by the time rollover finishes, the disk version is treated like an external edit and routed through the existing conflict path instead of clobbering the buffer.
- App Open Loops: the sidebar Open Loops item now shows a read-only SwiftUI surface backed by `OpenLoops.grouped`, with quiet source metadata and no mutation controls. The sidebar count comes from the real read model rather than the old fake count.
- Docs: README and ROADMAP now list `rollover`, `end-of-day`, and the Milestone 3 close state. PARKING_LOT parks recurrence and keeps the unbuilt Open Loops buckets explicit.

### Acceptance criteria status

- Incomplete tasks from yesterday roll forward: pass.
- Completed tasks do not appear in Open Loops: pass.
- Duplicate rollovers are prevented: pass, including after database deletion and rebuild.
- Daily note remains clean Markdown: pass. Rolled tasks are normal Markdown bullets with a hidden HTML marker on the same line.

### Tests/Checks run

- `swift package clean && swift test --skip CommandTests`: 116 library tests, 0 failures.
- CLI tests via prebuilt bundle after `swift build --product daymark`: 17 tests, 0 failures (`CaptureCommandTests`, `OpenLoopsCommandTests`, `RolloverCommandTests`, `EndOfDayCommandTests`).
- `swift build --product Daymark`: app target links with the in-app Open Loops surface.

### Remaining

- Recurrence is parked; it is not part of the Milestone 3 acceptance criteria.
- Note-relative due resolution remains parked.
- Open Loops mutation actions such as mark done, defer, create Codex task, and recurring are later work.

## 2026-06-29 (Stocktake, quality review, and later-milestone sharpening)

Milestone 3 is accepted as complete. `main` is aligned with `origin/main` at `cb2ee4b`, and the working tree was clean before this stocktake.

### Quality assessment

- The strongest choice so far is architectural: Markdown is still the source of truth, SQLite remains rebuildable, and every mutating workflow writes readable files. That is the product's trust foundation.
- The most useful surface today is now the local task loop: capture, task parsing, rollover, Open Loops, and end-of-day review form a real daily workflow rather than a demo.
- The app remains appropriately quiet. The Open Loops surface is read-only and restrained, and no AI, network, Gmail, Calendar, cloud sync, app-bundle, or global-hotkey work leaked into the first four completed milestones.
- Test posture is strong for the current stage: rollover idempotency, rebuild behavior, CLI behavior, parser behavior, and store projections are covered. The known app/CLI product-name collision is documented and worked around in verification.

### Usefulness assessment

- Milestone 0 proved taste and gave the project a visual north star, but it was intentionally fake data.
- Milestone 1 made the app safe enough to point at the real `~/phoenix` workspace and survive external edits.
- Milestone 2 made capture useful through the in-app Slip and `daymark capture`, even though the true system-global hotkey is still deferred behind app-bundle work.
- Milestone 3 made Daymark meaningfully useful for daily commitments. The biggest remaining usefulness gap is mutation from Open Loops: mark done, defer, create Codex task, and recurring are still later work.
- Milestone 4 should now focus on turning messy note text into executable task files. That is the natural next usefulness jump because it connects Today's context to agent work without adding unsafe automation.

### Adjustments made

- Marked Milestone 3 as done in `README.md` and `docs/ROADMAP.md`.
- Marked Milestone 4 as the next milestone.
- Expanded Milestones 4 through 8 in `docs/ROADMAP.md` with build scope, non-goals, and acceptance anchors.
- Expanded `docs/ACCEPTANCE_CRITERIA.md` for Milestones 4 through 8, since the later milestones were previously too sparse to guide future sessions.

## 2026-06-29 (Milestone 4 first slice: Codex task file handoff)

Milestone 4 is active, and the first useful slice is complete: Daymark can turn selected text or the current Markdown block into a previewed Codex task draft, then write one approved Markdown task file under `specs/tasks/`.

### What changed

- `CodexTaskDraft` now carries source path, line range, block heading, source excerpt, constraints, acceptance criteria, and a suggested file path. Its Markdown output is plain enough for another agent to use without Daymark internals.
- `CodexTaskFileWriter` validates drafts, writes atomically under `specs/tasks/`, creates the directory when missing, and uses `-2`, `-3`, and later suffixes instead of overwriting existing task files.
- `SourceSelector` extracts selected text first, and otherwise selects the current Markdown block around the cursor. It handles paragraphs, list items with continuations, fenced code blocks, heading boundaries, blank-line cursor positions, and CRLF line numbers.
- `PreviewBuilder` now generates deterministic drafts without model calls. It derives a title from the first meaningful source line, creates a date-prefixed slug path, preserves the excerpt, and adds conservative default constraints and acceptance criteria.
- `daymark codex-task` adds a dry-run preview path and an `--apply` write path. Dry-run prints the exact Markdown and target path. Apply writes one file and prints the created path.
- The app editor now tracks selected text and cursor range. Command Shift C generates a real preview in the existing Codex Task Composer, and `Create Task File` writes only after approval.
- `docs/SELF_TEST_M4_CODEX_HANDOFF.md` gives Samay a safe manual test path using a temp workspace.

### Durable convention

ADR-007 records Codex task file naming: `specs/tasks/yyyy-mm-dd-title-slug.md`, with numeric suffixes for collisions. The generated task file carries the source note path and line metadata. The source note is not modified by this slice.

### Current verification

- Baseline before edits: `swift package clean && swift test --skip CommandTests`, 116 tests, 0 failures.
- Final library pass: `swift package clean && swift test --skip CommandTests`, 131 tests, 0 failures.
- CLI tests via prebuilt bundle after `swift build --product daymark`: 21 tests, 0 failures (`CodexTaskCommandTests`, `CaptureCommandTests`, `OpenLoopsCommandTests`, `RolloverCommandTests`, `EndOfDayCommandTests`).
- `swift build --product daymark` and `swift build --product Daymark` both link.
- Temp-workspace end-to-end pass: dry-run wrote nothing, apply wrote one task file, repeat apply created `-2`, the generated file included source and excerpt, and the source note was unchanged.
- `daymark doctor` against `~/phoenix` was read-only. It reported today's note missing for 2026-06-29 and advised `daymark init`; no mutation was performed.
- Slopcheck passed on every authored or edited source, test, and doc file in this slice.

### Remaining in Milestone 4

- Editable in-app preview fields are not built. The current app preview is read-only plus approval.
- Source-note backlinking is not built. It should stay separately approved and idempotent if added.
- Context bundle export is not built. Build it only after the task-file handoff has been used and tightened.
- Strong duplicate warnings are not built. Repeated approvals create visible, non-destructive suffix files.

## 2026-06-29 (Milestone 4 adversarial quality pass)

The first Codex handoff slice was reviewed against real use before consolidating. The main finding was concrete: placing the cursor on an empty section heading could generate a low-value task file from the heading text alone. That violated the intent of the feature, which is to hand off real note context, not section labels.

### What changed

- Hardened `SourceSelector` so headings act as anchors to the first real content block beneath them. Empty heading-only sections now throw `emptySource` instead of creating a draft.
- Added regression coverage for cursor-on-heading behavior, empty heading rejection, and heading-to-first-content selection.
- Removed the generic preview goal phrase and now derive the draft goal from the selected source paragraph. The source text is still preserved verbatim in the `Source Excerpt` section.
- Added a CLI guard so `daymark codex-task --line` fails when the requested line is beyond the source file instead of silently selecting the nearest block.
- Folded in the app icon resource packaging cleanly: SwiftPM copies `AppIcon.icns` and excludes source iconset assets from compilation warnings.
- Deleted the real-world placeholder task files that had been created during manual testing in `~/phoenix/specs/tasks/`, and restored the 2026-06-29 daily note to clean empty sections.

### Verification

- `swift test --filter SourceSelectorTests`: 10 tests, 0 failures.
- `swift test --filter DaymarkAgentsTests && swift test --filter CodexTaskGeneratorTests`: 18 tests, 0 failures.
- `python3 ~/.claude/scripts/slopcheck.py <changed text files>`: clean.
- `swift package clean && swift test --skip CommandTests`: 133 library tests, 0 failures.
- CLI tests via prebuilt bundle after `swift build --product daymark`: 22 tests, 0 failures (`CodexTaskCommandTests`, `CaptureCommandTests`, `OpenLoopsCommandTests`, `RolloverCommandTests`, `EndOfDayCommandTests`).
- `swift build --product daymark` and `swift build --product Daymark`: both link. The app target copies `AppIcon.icns` without the prior unhandled-resource warnings.
- Temp-workspace end-to-end: dry-run wrote nothing, apply wrote one task file, repeat apply wrote a `-2` suffix, empty heading selection failed, invalid line selection failed, and the source note stayed unchanged.
- `daymark doctor` against `~/phoenix`: read-only, today's note present, workspace directories present, database present.

### Status

Ready to consolidate and push to `main`.

## 2026-06-29 (Milestone 4 editable Codex task preview)

The next Codex handoff slice is complete. The in-app Codex Task Composer now lets Samay edit the generated draft before writing the approved task file.

### What changed

- Added `CodexTaskDraft.withEditedFields(...)` so edited title, goal, constraints, and acceptance criteria still flow through the same Markdown output and writer validation as CLI drafts.
- Cleaned edited list fields by trimming blank lines and stripping Markdown bullet or checkbox prefixes before generating the final file.
- Added tests for edited Markdown output, blank edited draft rejection, title-edit slug refresh, collision suffixes after title edits, constraint cleanup, criteria cleanup, and default acceptance-criteria deduping.
- Replaced the read-only in-app composer fields with editable title, goal, constraints, and acceptance criteria controls.
- Kept source path, source line or block, source excerpt, target path, and generated Markdown read-only in the composer.
- Kept file I/O off the typing path. Existing task paths and the preview date are captured when the preview is created, local edit buffers handle field typing, and the writer rechecks collisions only when `Create Task File` is clicked.
- Locked title-edit slug generation to the original preview date so an open composer cannot drift to a different date prefix while Samay is editing.
- Improved create failure messages for blank drafts and invalid paths.
- Updated `README.md`, `docs/ROADMAP.md`, `docs/PARKING_LOT.md`, and `docs/SELF_TEST_M4_CODEX_HANDOFF.md` so the production surfaces no longer describe editable preview as parked.

### Verification

- Red-green check: `swift test --filter CodexTaskGeneratorTests` first failed because `CodexTaskDraft.withEditedFields(...)` did not exist, then passed after implementation.
- Targeted final: `swift test --filter CodexTaskGeneratorTests`, 9 tests, 0 failures.
- Library suite: `swift package clean && swift test --skip CommandTests`, 137 tests, 0 failures.
- CLI bundle after `swift build --product daymark`: 22 tests, 0 failures (`CodexTaskCommandTests`, `CaptureCommandTests`, `OpenLoopsCommandTests`, `RolloverCommandTests`, `EndOfDayCommandTests`).
- Temp-workspace end-to-end: dry-run wrote nothing, apply wrote one task file, repeat apply wrote a `-2` suffix, empty heading selection failed, invalid line selection failed, and the source note stayed unchanged.
- `swift build --product Daymark`: app target links.
- App launch check: `swift run Daymark` launched for 4 seconds against a temp workspace and was stopped; no real `~/phoenix` mutation was used for the app check. Hands-on UI interaction still needs Samay's app pass.
- `swift build --product daymark && .build/arm64-apple-macosx/debug/daymark doctor`: read-only doctor passed against `~/phoenix`; today's note, workspace folders, and database were present.
- `python3 ~/.claude/scripts/slopcheck.py <changed files>` reported 0 kill-list hits and 0 warnings. It reported a structural exclamation count from Swift syntax and an existing test string, not prose.

### Remaining in Milestone 4

- Run a real hands-on app pass with the editable composer and tighten any field focus, scrolling, or layout roughness that appears in use.
- Context bundle export is the next substantial M4 slice: preview a small source bundle for an approved task and write it under `artifacts/context-bundles/` only after approval.
- Source-note backlinking remains parked unless separately approved. If built, it must be idempotent and gated separately from task-file creation.
- Strong duplicate warnings remain parked. Current behavior is still safe: repeated approvals write suffix files instead of overwriting.

## 2026-06-29 (Milestone 4 context bundle CLI slice)

The next Codex handoff slice is started and useful from the CLI. Daymark can now preview and write one context bundle from an approved Codex task file.

### What changed

- Added `CodexContextBundle`, a readable Markdown bundle with task path, goal, source path, source line or range, source block, source excerpt, constraints, and acceptance criteria.
- Added `CodexContextBundleWriter`, which writes atomically under `artifacts/context-bundles/`, creates the directory as needed, and suffixes repeat writes instead of overwriting.
- Added `daymark context-bundle --task ...` for dry-run preview and `--apply` for the approved write.
- Added conservative parsing of Daymark-generated Codex task Markdown. The CLI expects the task-file shape Daymark writes rather than trying to import arbitrary Markdown.
- Split context bundle code into `CodexContextBundle.swift` so `CodexTaskDraft.swift` stays focused on task drafts and task-file writes.
- Hardened bundle validation so a bundle must point back to a `specs/tasks/*.md` task file and write only under `artifacts/context-bundles/*.md`.
- Recorded context bundle naming in ADR-008.
- Updated `README.md`, `docs/ROADMAP.md`, `docs/PARKING_LOT.md`, and `docs/SELF_TEST_M4_CODEX_HANDOFF.md`.

### Verification

- Red-green check: the first bundle test failed because `CodexContextBundle` did not exist, then passed after implementation.
- Targeted core: `swift test --filter CodexTaskGeneratorTests`, 12 tests, 0 failures.
- CLI bundle after `swift build --product daymark`: `DaymarkCLITests.CodexTaskCommandTests`, 7 tests, 0 failures.
- Library suite: `swift package clean && swift test --skip CommandTests`, 140 tests, 0 failures.
- CLI regression bundle after `swift build --product daymark`: 24 tests, 0 failures (`CodexTaskCommandTests`, `CaptureCommandTests`, `OpenLoopsCommandTests`, `RolloverCommandTests`, `EndOfDayCommandTests`).
- Temp-workspace end-to-end: Codex task dry-run wrote nothing, task apply wrote one file, repeat task apply wrote a `-2` suffix, empty heading and invalid line failed, context-bundle dry-run wrote nothing, context-bundle apply wrote one file, repeat bundle apply wrote a `-2` suffix, and both the source note and original task file stayed unchanged.
- `swift build --product daymark` and `swift build --product Daymark` both linked.
- `swift build --product daymark && .build/arm64-apple-macosx/debug/daymark doctor`: read-only doctor passed against `~/phoenix`.
- `python3 ~/.claude/scripts/slopcheck.py <changed files>` reported 0 kill-list hits and 0 warnings. The remaining structural notes came from Swift syntax and test strings, not prose.
- The em dash scan found no matches. `git diff --check` was clean.

### Remaining in Milestone 4

- Wire context bundle preview and approval into the app after a Codex task file is created.
- Keep source-note backlinking parked unless separately approved and idempotent.
- Do a real hands-on app pass before consolidating if this working tree is going to be committed as one slice.

## 2026-06-29 (Milestone 4 in-app context bundle approval)

The next Codex handoff slice is complete in code. After an in-app Codex task file is created, Daymark now offers a compact context bundle preview and requires a second explicit approval before writing the bundle.

### What changed

- `AppState` now records the exact draft and relative path that were approved for task-file creation.
- Editing the task draft after creation clears the created-task receipt and any bundle preview, so a later bundle cannot drift away from the approved task file.
- Added in-app context bundle state, preview, approval, cancellation, and error messaging using `CodexContextBundle` plus `CodexContextBundleWriter`.
- Added a quiet right-margin `Context Bundle` panel that shows the created task path, the read-only target bundle path, and the exact Markdown from `CodexContextBundle.markdown()`.
- `Create Context Bundle` writes exactly one bundle file per approval under `artifacts/context-bundles/` and leaves both the source note and task file untouched.
- Added core tests for collision-safe bundle preview paths and writer-side collision rechecks at approval time.
- Updated README, ROADMAP, PARKING_LOT, and the M4 self-test with the in-app bundle flow.

### Verification

- Baseline before edits: `swift package clean && swift test --skip CommandTests`, 140 tests, 0 failures.
- Baseline products before edits: `swift build --product daymark`, `swift build --product Daymark`, and read-only `.build/arm64-apple-macosx/debug/daymark doctor` after rebuilding the CLI product.
- Baseline app launch: `swift run Daymark` started against a temp workspace and was stopped without touching `~/phoenix`.
- Targeted after edits: `swift test --filter CodexTaskGeneratorTests`, 14 tests, 0 failures.
- Library suite: `swift package clean && swift test --skip CommandTests`, 142 tests, 0 failures.
- CLI regression bundle after `swift build --product daymark`: 24 tests, 0 failures (`CodexTaskCommandTests`, `CaptureCommandTests`, `OpenLoopsCommandTests`, `RolloverCommandTests`, `EndOfDayCommandTests`).
- `swift build --product Daymark`: app target links.
- Temp-workspace end-to-end: Codex task dry-run wrote nothing, task apply wrote one file, repeat task apply wrote a `-2` suffix, empty heading and invalid line failed, context-bundle dry-run wrote nothing, context-bundle apply wrote one file, repeat bundle apply wrote a `-2` suffix, and both the source note and original task file stayed unchanged.
- App launch check: `swift run Daymark` launched against a temp workspace and was stopped. I did not complete hands-on keyboard/UI interaction in this environment.
- `swift build --product daymark` followed by read-only `.build/arm64-apple-macosx/debug/daymark doctor`: passed against `~/phoenix`; today's note, workspace folders, and database were present.

### Remaining in Milestone 4

- Do one real hands-on app pass for the full Command Shift C flow: editable task draft, task approval, bundle preview, bundle approval, and unchanged source note.
- Decide whether to close Milestone 4 as preview-and-approval handoff or add a separately approved, idempotent source-note backlink slice.
- Keep Codex execution, backlinking, dynamic blocks, app-bundle work, and global hotkey work parked unless separately approved.

## 2026-06-29 (Milestone 4 closeout gate)

Milestone 4 is ready to close. The closeout pass verified the Codex Handoff loop, found one real stale-state issue, fixed it, and left source-note backlinking parked.

### What changed

- Fixed `AppState.previewCodexTaskFromSelection()` so starting a fresh task preview clears any previous created-task receipt, bundle preview, and bundle message.
- Reused that same clearing helper when editing or dismissing a task draft, keeping the bundle offer tied to one approved task file.
- Marked Milestone 4 done in `docs/ROADMAP.md`.
- Updated `README.md` to describe Codex Handoff as complete.
- Updated `docs/PARKING_LOT.md` with the recommendation to keep source-note backlinking parked unless real use proves it is needed.

### Closeout review

- Task Markdown has one domain source: `CodexTaskDraft.markdown()`.
- Bundle Markdown has one domain source: `CodexContextBundle.markdown()`.
- App bundle preview uses `CodexContextBundle.from(...)`, the same model that `CodexContextBundleWriter` writes.
- Task and bundle writers both recheck collisions at approval time.
- Source notes are not written by task creation or bundle creation.
- Bundle creation does not mutate the task file.
- Title edits update the suggested task slug from the stored preview date and path basis, without scanning the filesystem on every keystroke.
- Validation failures stay local and user-facing in the composer messages.
- No model, network, Codex execution, Gmail, Calendar, dynamic block, app-bundle, or global-hotkey work was added.

### App notes

- Launched `swift run Daymark` against a temp workspace with a sample daily note containing a heading, task line, and paragraph.
- Triggered Command Shift C in the temp-workspace app and visually confirmed the right-side composer showed editable title, goal, constraints, and acceptance criteria.
- Visually confirmed source metadata, source excerpt, target path, and Markdown preview were shown as read-only fields.
- Source-note and task-file unchanged checks for the actual write paths were verified through temp-workspace CLI end-to-end because macOS Accessibility automation could not reliably press the SwiftUI approval buttons in this environment.

### Backlink recommendation

Close Milestone 4 without source-note backlinking. The generated task file and context bundle already carry the source path, line or block, source excerpt, constraints, and acceptance criteria that another agent needs. A backlink would add source-note mutation risk to a handoff flow that is already useful without it. If later use shows that Samay needs a return link inside the source note, build it as a separate explicit, idempotent approval.

### Verification

- Initial closeout suite: `swift package clean && swift test --skip CommandTests`, 142 tests, 0 failures.
- Initial product checks: `swift build --product daymark`, `swift build --product Daymark`, then rebuilt `daymark` and ran read-only `.build/arm64-apple-macosx/debug/daymark doctor` against `~/phoenix`.
- App temp-workspace pass: `swift run Daymark` launched against `/tmp/daymark-m4-app3...`; the composer preview was visually verified without mutating `~/phoenix`.
- Final library suite: `swift package clean && swift test --skip CommandTests`, 142 tests, 0 failures.
- Final CLI regression bundle after `swift build --product daymark`: 24 tests, 0 failures.
- Final app product: `swift build --product Daymark` linked.
- Final temp-workspace end-to-end: task dry-run wrote nothing, task apply wrote one file, repeat task apply wrote `-2`, bad line failed, empty heading failed, bundle dry-run wrote nothing, bundle apply wrote one file, repeat bundle apply wrote `-2`, and the source note plus original task file hashes stayed unchanged.
- Final read-only doctor after rebuilding `daymark`: `.build/arm64-apple-macosx/debug/daymark doctor` passed against `~/phoenix`.
- Final text gates: slopcheck reported 0 kill-list hits and 0 warnings for the edited files, the em dash scan found no matches, and `git diff --check` was clean.

## 2026-06-29 (Milestone 4 closeout: adversarial review and consolidation)

An adversarial review of the in-app context bundle slice found no correctness bugs but several real duplications. This pass removed them without changing behavior, then shipped Milestone 4 to `main`.

### What changed

- Added `WorkspaceRoot.existingMarkdownRelativePaths(under:)` and routed all six callers through it. The "scan a workspace subdirectory, keep `.md` files, return relative paths" logic had been copied across `CodexTaskDraft`, `CodexContextBundle`, the CLI (twice), and `AppState` (twice). One source now backs task and bundle collision safety in every module.
- Extracted the duplicated read-only field box into a shared `ReadOnlyField` view and the duplicated right-margin panel chrome into a `marginPanel()` modifier, both in `Components.swift`. The Codex Task Composer and Context Bundle panels share them.
- Replaced the three-way nil check that revealed the bundle panel with an `AppState.showsContextBundlePanel` computed property.
- Added direct `WorkspaceRoot` tests for the new path helper.

### Verification

- `swift build` and `swift build --product daymark` both link.
- Library suite: `swift test --skip CommandTests`, 144 tests, 0 failures (two new `WorkspaceTests`).
- Full suite from the prebuilt bundle: `xcrun xctest .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest`, 166 tests, 0 failures, including all 24 CLI command tests.
- Temp-workspace end-to-end on the rebuilt binary: task and bundle dry-runs wrote nothing, repeat applies produced `-2` suffixes, an invalid line was rejected, and the source note hash was unchanged.
- `git diff --check` clean.

### CLI test harness note

`swift test --filter CommandTests` corrupts the `daymark` binary through the documented dual-`@main` relink collision, so every spawned-process test times out. That produces a 10 minute run with 104 failures, which is a harness artifact and not a regression. Run CLI tests from the prebuilt bundle instead: `swift build --product daymark`, then `xcrun xctest -XCTest <ClassName> .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest`. A durable fix for the harness is parked.

## 2026-06-29 (Milestone 5 first slice: Dynamic Blocks CLI preview and apply)

Milestone 5 is active. The first useful Dynamic Blocks slice is complete for `/daymark open-loops`: Daymark parses visible commands from Markdown, renders deterministic local output from existing task parsing and Open Loops grouping, previews the generated region, and writes only on explicit `--apply`.

### What changed

- Added a Dynamic Blocks domain path in `DaymarkCore`: command invocations with source path, line number, raw command text, command name, arguments, ordinal, and stable command hash.
- Added parser coverage for `/daymark open-loops`, `/daymark open-loops #tag`, multiple commands, CRLF input, fenced-code skipping, and clear unsupported-command errors.
- Added an Open Loops renderer that reuses `OpenLoops.grouped`, excludes completed tasks, preserves deterministic bucket order, and supports exact tag arguments such as `#deal/acme`.
- Added a patch planner that inserts or replaces one generated Markdown region below the visible command. The generated region uses `<!-- daymark:block-begin <hash> -->` and `<!-- daymark:block-end <hash> -->` markers.
- Added generated-region stripping before task parsing so generated checklist lines do not become source tasks on the next refresh.
- Added `daymark blocks refresh --source <path>` for dry-run preview and `--apply` for explicit target-note writes. The CLI scans daily Markdown directly for this slice, so dry-run does not need to create or mutate `.daymark`.
- Added `docs/SELF_TEST_M5_DYNAMIC_BLOCKS.md` and ADR-009 for the marker convention.

### Verification

- TDD red checks: the first core test run failed on missing Dynamic Blocks types; the first CLI test run failed on unknown `blocks`; the recursive-render regression failed before adding generated-region stripping.
- DynamicBlockTests are included in the clean library suite: 7 tests, 0 failures.
- Focused CLI suite after rebuilding `daymark`: `xcrun xctest -XCTest DaymarkCLITests.DynamicBlocksCommandTests .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest`, 1 test, 0 failures.
- Clean library suite: `swift package clean && swift test --skip CommandTests`, 151 tests, 0 failures.
- CLI regression bundle after `swift build --product daymark`: 25 tests, 0 failures, including `DynamicBlocksCommandTests`, `CodexTaskCommandTests`, `CaptureCommandTests`, `OpenLoopsCommandTests`, `RolloverCommandTests`, and `EndOfDayCommandTests`.
- App product: `swift build --product Daymark` linked.
- Temp-workspace end-to-end: dry-run wrote nothing, apply wrote one generated region, repeat apply was byte-stable, completed tasks were excluded, exact tag filtering worked, edits before and after the block were preserved, deleting `.daymark` did not affect idempotency, and only the two test Markdown notes existed after the flow.
- Read-only doctor after rebuilding `daymark`: `.build/arm64-apple-macosx/debug/daymark doctor` passed against `~/phoenix`.

### Remaining in Milestone 5

- Add rebuildable `.daymark` cache metadata for dynamic block renders without making cache authoritative.
- Add the next renderer, likely `source-list`, only after the cache choice is settled.
- Add app affordance or manual refresh only after the CLI/domain path has real use.
- Keep Calendar, Gmail, AI summaries, Codex execution, automatic refresh, and arbitrary plugin blocks out of scope.

## 2026-06-29 (Milestone 5 hardening and Dynamic Blocks cache metadata)

The M5 first slice is hardened and now includes rebuildable `.daymark` cache metadata for approved dynamic block applies. Markdown remains authoritative: preview and apply still derive from visible `/daymark ...` commands plus generated-region markers, and cache deletion or corruption does not control correctness.

### What changed

- Added `DynamicBlockCacheStore` and `DynamicBlockCacheRecord`, writing a versioned JSON metadata file at `.daymark/dynamic-blocks.json`.
- Cache records include source path, command hash, raw command, renderer name, rendered output hash, and refreshed timestamp.
- Wired `daymark blocks refresh --apply` to record cache metadata after the target note update. Dry-run still writes nothing.
- Hardened `WorkspaceIndexer` so task projection strips dynamic generated regions before parsing checkboxes. This prevents generated Open Loops checklist lines from feeding back into SQLite after `daymark rebuild`.
- Made cache recording rebuild bad metadata by overwriting invalid cache JSON from the current Markdown-derived patch plan.
- Updated ADR-010, the M5 self-test, README, roadmap, and parking lot to reflect the cache convention and remaining M5 scope.

### Verification

- TDD red checks: the indexer regression first projected both real and generated tasks; the cache store test first failed because the store did not exist; the CLI cache test first failed because apply did not write `.daymark/dynamic-blocks.json`; the invalid-cache test first failed on JSON decoding.
- Focused green checks: indexer generated-region stripping, cache record/update, corrupt-cache overwrite, and dynamic blocks CLI cache behavior all passed after implementation.
- Clean library suite: `swift package clean && swift test --skip CommandTests`, 154 tests, 0 failures.
- CLI product and regression bundle: `swift build --product daymark`, then `xcrun xctest -XCTest DaymarkCLITests.DynamicBlocksCommandTests,DaymarkCLITests.CodexTaskCommandTests,DaymarkCLITests.CaptureCommandTests,DaymarkCLITests.OpenLoopsCommandTests,DaymarkCLITests.RolloverCommandTests,DaymarkCLITests.EndOfDayCommandTests .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest`, 25 tests, 0 failures.
- App product: `swift build --product Daymark` linked.
- Temp-workspace end-to-end: dry-run wrote no note and no cache, apply wrote one generated region plus cache metadata, repeat apply left the note byte-stable, edits outside the region were preserved, an injected generated checkbox did not feed back after rebuild/open-loops, deleting `.daymark` left refresh idempotent and recreated cache metadata.
- Read-only doctor after rebuilding the CLI: `.build/arm64-apple-macosx/debug/daymark doctor` passed against `~/phoenix`.
- Hygiene checks: `git diff --check` clean, `python3 ~/.claude/scripts/slopcheck.py <changed files>` clean, and em dash scan over changed files found no hits.

### Remaining in Milestone 5

- Add the next deterministic renderer, likely `source-list`, using the same parser, patch, preview, apply, and cache path.
- Add a restrained app affordance only after the CLI/domain behavior has more use.
- Keep Calendar, Gmail, AI summaries, Codex execution, automatic refresh, and arbitrary plugin blocks out of scope.

## 2026-06-29: M5 quality and architecture hardening pass

A focused hardening pass before adding more Milestone 5 renderers. Investigation was run as a
read-only multi-agent review (eight tracks, each finding adversarially verified against the
code), then implemented as one integrated slice on `main`.

### Dynamic Blocks safety

- `daymark blocks refresh --source` is now confined to the workspace. `WorkspaceRoot.containedFile` canonicalizes the path and rejects absolute paths and `..` escapes, so `--apply` can never overwrite a file outside `~/phoenix`. The canonical workspace-relative path is passed to the planner so command hashes match the indexer.
- Generated-region stripping (`DynamicBlockRegion.removingGeneratedRegions`) now removes only complete begin/end pairs matched by hash. An unterminated or hand-edited begin marker no longer silently drops every following task from the projection and index.
- The patch planner bounds an existing region by the begin marker's own hash, not the new invocation hash, so editing a command's text still finds and replaces its region in place. A begin marker with no matching end fails clearly.
- `DynamicBlockPatchPlan.apply` preserves the file's dominant line ending. A CRLF note stays CRLF; an LF note stays LF. No untouched line is silently rewritten.
- Fence detection moved to a shared `MarkdownFenceScanner` (Core/Support) used by both `DynamicBlockParser` and `TaskParser`. It matches CommonMark fence type and length, so a `/daymark` command or example checkbox inside a mixed or longer code fence is no longer executed or parsed.
- The dynamic-block cache tolerates duplicate decodable records (last write wins) instead of trapping, and the CLI records the cache after the note write inside a warn-on-failure block so a cache error never fails an already-successful apply.

### Canonical Markdown projection

- New `DailyMarkdownProjectionReader` (DaymarkIndexer) is the single daily-Markdown projection path: enumeration, workspace-relative path, and per-file projection (read, strip generated regions, parse blocks and tasks). `WorkspaceIndexer` and the CLI both route through it; the CLI's private daily-scanning and relative-path duplicates were deleted.
- `WorkspaceIndexer.rebuild()` now reconciles the index against the files on disk and prunes projections (and cascaded blocks, tasks, and search rows) for daily notes deleted from disk, so stale open tasks can no longer be resurrected.
- `daymark open-loops` reads fresh from the Markdown files (no DB open, no prior `rebuild` needed), so it always reflects the files on disk.

### Store atomicity

- `Database.replaceNoteProjection` wraps the note upsert, FTS refresh, block replacement, and task replacement in one transaction via a new `withTransaction` helper. `NoteRepository.projectNote` is now a thin delegate; the multi-table consistency boundary lives in the actor. `deleteNote` runs its two deletes in the same transaction. `busy_timeout` is set so contended multi-connection writers wait rather than fail immediately.

### Codex handoff

- The Codex task-file parser moved into `DaymarkCore` beside `CodexTaskDraft.markdown()` as `CodexTaskDraft.parse(taskMarkdown:taskRelativePath:)`, fence-aware so a Source Excerpt containing `## ` headings or its own code fences round-trips verbatim. The excerpt writers now compute a fence long enough to wrap any backtick run in the content. The CLI reads the file and calls the Core parser, keeping its `validate` gate. The stale, unused `PreviewBuilder.codexTaskPreview(title:selectedText:sourcePath:)` overload was deleted.

### App state boundary

- `AppState` now holds one `CreatedCodexTask` value instead of two parallel optionals, and exposes `canCreateCodexTaskFile` / `canCreateCodexContextBundle` backed by `isWritable` predicates on the Core types, so the composer views no longer instantiate file writers just to evaluate button state.

### Deliberately not done

- Removing the app's silent rollover-on-launch was implemented and then reverted at the user's request. It is a real tension with the preview-before-execution invariant, but removing it without an in-app preview/approval surface (out of M5 scope) would regress the M3 "tasks roll forward" behavior in the app. Parked as a deliberate future product decision in `docs/PARKING_LOT.md`; no behavior change shipped.
- The CLI test-support extraction (C1), the per-command file split, and the arg-parse dedup were parked to avoid churning an actively edited file during a behavior-hardening pass. See `docs/PARKING_LOT.md`.

### Verification

- Clean library suite: `swift package clean && swift test --skip CommandTests`, 180 tests, 0 failures (was 154; new coverage for fence matching, unterminated regions, CRLF, hash-bound regions, duplicate cache, workspace path confinement, Codex round-trip, atomic projection, deleted-note prune, and reader/SQLite parity).
- CLI command bundle: built the test bundle, then `swift build --product daymark` last (the `Daymark`/`daymark` case-insensitive collision means the CLI must be the final build before running), then `xcrun xctest` over all six `*CommandTests`, 34 tests, 0 failures.
- App product `swift build --product Daymark` linked; read-only `daymark doctor` passed against `~/phoenix`.
- Hygiene: `git diff --check` clean, zero em dashes in changed files, zero slopcheck kill-list hits across changed Swift files (structural prose heuristics on code syntax ignored).

### Docs aligned

- Amended ADR-003 (SQLite is the index, task projection, and FTS store, not the event log or dynamic-block cache; the cache is JSON per ADR-010). Corrected `ARCHITECTURE.md` module map, data flows, and schema list (implemented vs planned). Corrected the `.daymark` layout in `PRODUCT_SPEC.md`. Added a built-vs-planned note to `INTERACTION_SPEC.md`. Recorded the parked items and documentation stubs in `PARKING_LOT.md`. Added the safety/idempotency checks to `SELF_TEST_M5_DYNAMIC_BLOCKS.md`.

## 2026-06-29: M5 source-list renderer

The next deterministic Dynamic Blocks renderer is implemented for `/daymark source-list #tag`.
It uses the same visible command, preview, apply, generated-region marker, and cache path as
`open-loops`. Markdown remains authoritative and cache remains rebuildable metadata.

### What changed

- Added `DynamicBlockSource` and a `source-list` renderer in `DaymarkCore`. It accepts one exact tag argument such as `#project/daymark`, renders compact Markdown with title plus relative path, sorts deterministically by path, and shows a plain Markdown empty state when no tag is supplied.
- Extended `DailyMarkdownProjectionReader` with a workspace Markdown source scan. It extracts source tags from local Markdown, skips hidden `.daymark` state, strips generated dynamic-block regions before matching, and ignores visible `/daymark ...` command lines so a `source-list` command does not make its own note match.
- Wired `daymark blocks refresh` to pass both task projection and source inventory into the existing patch planner. Dry-run still writes nothing; `--apply` writes one approved target note and records `.daymark/dynamic-blocks.json` metadata after the note write.
- Updated README, CLAUDE.md, roadmap, parking lot, and the M5 self-test so production surfaces name `source-list` as shipped and keep app refresh, `codex-context`, and `weekly-review` parked.

### Verification

- TDD red checks: the core source-list renderer test first failed on missing `DynamicBlockSource` and missing `sources:` render input; the reader test first failed on missing `allSources`; the CLI test first failed with "No sources found" because the CLI was not passing source inventory into the planner.
- Focused green checks: `DynamicBlockTests`, `DynamicBlockSafetyTests`, and `DailyMarkdownProjectionReaderTests`, 24 tests, 0 failures.
- Clean library suite: `swift package clean && swift test --skip CommandTests`, 183 tests, 0 failures.
- CLI command bundle: `swift build --build-tests`, `swift build --product daymark`, then `xcrun xctest` over the six command-test classes, 35 tests, 0 failures.
- Product builds: `swift build --product daymark` and `swift build --product Daymark` both linked.
- Temp-workspace end-to-end: one note containing `/daymark open-loops #deal/acme` and `/daymark source-list #project/daymark`; dry-run left the note unchanged and wrote no cache; apply wrote exactly two generated regions and cache records for both renderers; repeat apply was byte-stable; generated Open Loops checkboxes did not feed back into `daymark open-loops`; deleting `.daymark` and applying again recreated cache metadata without changing the note.
- Read-only doctor after rebuilding the CLI: `.build/arm64-apple-macosx/debug/daymark doctor` passed against `~/phoenix`.

### Remaining in Milestone 5

- Build the next deterministic renderer as its own slice, likely `/daymark codex-context #project/daymark`, if the local source-selection semantics are clear enough to stay deterministic.
- Keep automatic app refresh parked until the CLI/domain path has more use.
- Keep app rollover preview/approval as a separate product decision; the app launch path still auto-applies rollover to preserve Milestone 3 behavior.

## 2026-06-29: M5 codex-context renderer

The third deterministic Dynamic Blocks renderer is implemented for `/daymark codex-context #tag`.
It uses the same visible command, preview, apply, generated-region marker, and cache path as
`open-loops` and `source-list`. The renderer only reports existing local Codex handoff artifacts;
it does not create task specs, refresh context bundles, mutate source notes, call models, or run Codex.

### What changed

- Added a compact Codex Context renderer in `DaymarkCore`. It accepts one exact tag argument such as `#project/daymark`, lists matching task specs under `specs/tasks/`, lists matching context bundles under `artifacts/context-bundles/`, includes task and source path provenance when known, sorts deterministically, and shows a plain Markdown empty state.
- Extended `DailyMarkdownProjectionReader` with local Codex artifact projection. It scans existing task specs and context bundles, strips generated dynamic-block regions before matching, ignores hidden `.daymark` state, matches direct artifact tags, and inherits tags through referenced source notes or task specs.
- Wired `daymark blocks refresh` to pass task projection, source inventory, and Codex artifact inventory into the existing patch planner. Dry-run still writes nothing; `--apply` writes only the approved target note and records rebuildable `.daymark/dynamic-blocks.json` metadata after the note write.
- Tightened shared tag extraction so punctuation at the end of a sentence, such as `#project/daymark.`, does not prevent deterministic local matching.
- Updated README, CLAUDE.md, roadmap, parking lot, and the M5 self-test so production surfaces name `codex-context` as shipped and keep app refresh plus `weekly-review` parked.

### Verification

- TDD red checks: the core renderer test first failed on missing `DynamicBlockCodexContextArtifact` and missing `codexContexts:` render input; the reader test first failed on missing `allCodexContexts`; the CLI test was added before CLI support and then passed after the CLI began passing Codex artifact inventory into the planner.
- Focused green checks: `DynamicBlockTests/testCodexContextRendererListsMatchingTaskSpecsAndBundles`, `DynamicBlockTests/testCodexContextRendererRejectsMalformedArgumentsAndShowsPlainEmptyState`, `DailyMarkdownProjectionReaderTests/testAllCodexContextsMatchesArtifactsByTagAndTaggedSourcePath`, and `DynamicBlocksCommandTests/testBlocksRefreshCodexContextDryRunApplyAndRepeatApplyAreIdempotent`, 4 tests, 0 failures.
- Baseline before edits: `swift package clean && swift test --skip CommandTests`, 183 tests, 0 failures; `swift build --build-tests`, `swift build --product daymark`, `swift build --product Daymark`, rebuilt CLI, and read-only `daymark doctor` all passed.
- Existing-renderer temp workspace before edits: `/daymark open-loops #deal/acme` and `/daymark source-list #project/daymark` preview wrote nothing, apply wrote two generated regions plus cache metadata, repeat apply was stable, and deleting `.daymark` recreated cache metadata without changing correctness.

### Remaining in Milestone 5

- Build `/daymark weekly-review` as the next deterministic renderer only if it can stay compact and local.
- Keep automatic app refresh parked until the CLI/domain path has more use across the three shipped renderers.
- Keep app rollover preview/approval as a separate product decision; the app launch path still auto-applies rollover to preserve Milestone 3 behavior.

## 2026-06-29: M5 weekly-review renderer

The fourth deterministic Dynamic Blocks renderer is implemented for `/daymark weekly-review`.
It uses the same visible command, preview, apply, generated-region marker, and cache path as
the other M5 renderers. The renderer is a local review scaffold, not a narrative summary.

### What changed

- Added a compact Weekly Review renderer in `DaymarkCore`. It accepts no arguments, uses the existing CLI `--date` value as the week anchor, lists current open tasks through the Open Loops grouping, lists completed tasks from daily notes in the anchored week, lists Codex task specs and context bundles dated in that week, and lists source notes referenced by those handoffs.
- Kept the renderer on the existing `DynamicBlockPatchPlanner` path. Dry-run writes nothing; `--apply` writes only the approved target note and records rebuildable `.daymark/dynamic-blocks.json` metadata after the note write.
- Added focused core and CLI coverage for weekly-review output, malformed arguments, generated-region stripping, dry-run, apply, repeat apply, cache recreation after `.daymark` deletion, and unchanged user text outside generated regions.
- Updated README, CLAUDE.md, roadmap, parking lot, and this self-test surface so production docs name `weekly-review` as shipped and keep app refresh parked as the remaining M5 slice.

### Verification

- Baseline before edits: `swift package clean && swift test --skip CommandTests`, 186 tests, 0 failures; `swift build --build-tests`, `swift build --product daymark`, `swift build --product Daymark`, rebuilt CLI, and read-only `daymark doctor` all passed.
- TDD red check: `DynamicBlockTests/testWeeklyReviewRendererIncludesOpenTasksCompletedTasksAndRecentHandoffs` first failed with `unsupportedRenderer(.weeklyReview)`.
- Focused green checks: `DynamicBlockTests`, `DailyMarkdownProjectionReaderTests`, and `DynamicBlocksCommandTests`, 30 tests, 0 failures.
- Hygiene: slopcheck passed for every changed source, test, and doc file; no em dashes in changed files; `git diff --check` clean.
- Full library suite: `swift package clean && swift test --skip CommandTests`, 188 tests, 0 failures.
- CLI command bundle: `swift build --build-tests`, `swift build --product daymark`, then `xcrun xctest` over the six command-test classes that exist in the repo, 37 tests, 0 failures. Context-bundle CLI coverage remains in `CodexTaskCommandTests`; there is no separate `ContextBundleCommandTests` class.
- Product builds: `swift build --product daymark` and `swift build --product Daymark` both linked.
- Temp-workspace end-to-end: one note containing `/daymark open-loops #deal/acme`, `/daymark source-list #project/daymark`, `/daymark codex-context #project/daymark`, and `/daymark weekly-review`; dry-run left the note unchanged and wrote no cache; apply wrote exactly four generated regions and cache records; repeat apply was byte-stable; user edits before and after generated regions were preserved; a generated task-looking checkbox injected inside a generated region did not feed back into preview output; deleting `.daymark` recreated cache metadata without changing note correctness.
- Read-only doctor after rebuilding the CLI: `.build/arm64-apple-macosx/debug/daymark doctor` passed against `~/phoenix`.

### Remaining in Milestone 5

- Design and build an app refresh affordance only after a focused app UX pass. The CLI/domain renderer set is now broad enough for that separate slice.
- Keep app rollover preview/approval as a separate product decision; the app launch path still auto-applies rollover to preserve Milestone 3 behavior.
- Keep source-note backlinking, Codex execution, model calls, network calls, app-bundle work, and global hotkey work parked unless separately approved.

## WHERE WE LEFT OFF

### Active Milestone

Milestone 5: Dynamic Blocks is active. The CLI/domain renderer set is now implemented for `/daymark open-loops`, `/daymark source-list #tag`, `/daymark codex-context #tag`, and `/daymark weekly-review` through the same preview, apply, marker, and cache path.

### Start Here Next

1. Run the full verification gate for the weekly-review slice if this session has not already completed it, then decide whether to commit and push the slice.
2. Start the app refresh design/build slice only after a focused UX pass. It must preserve preview-before-write and must not refresh while typing.
3. App rollover preview/approval is a separate, ADR-worthy product decision (see `docs/PARKING_LOT.md`); the launch path still auto-applies and that is intentional for now.
4. Keep source-note backlinking, Codex execution, model calls, network calls, app-bundle work, and global hotkey work parked unless separately approved.

### Current Truths

- Milestone 0 is complete.
- Milestone 1 is complete.
- Milestone 2 is closed. Capture is implemented and hardened: monthly Slip file, append to Today, promote to task, discard, and a `daymark capture` CLI. The system-global hotkey is deferred behind an app-bundle ADR.
- Milestone 3 is closed. Tasks are parsed with due and source metadata, projected into a rebuildable `tasks` table, rolled forward through a Markdown-derived dedup marker, and surfaced through CLI plus the in-app Open Loops view.
- Milestone 4 is closed and on `main`. It supports selected text or current Markdown block to a previewed draft, an approved single-file write under `specs/tasks/`, editable in-app preview fields before approval, CLI context bundle preview/apply under `artifacts/context-bundles/`, and in-app context bundle preview/approval after task-file creation.
- One helper, `WorkspaceRoot.existingMarkdownRelativePaths(under:)`, backs collision-safe naming for tasks and bundles across the writers, the CLI, and `AppState`. The right-margin panels share `ReadOnlyField` and the `marginPanel()` modifier from `Components.swift`.
- The first slice has been hardened after real testing: empty heading-only sections are rejected, generic goal text was removed, bad CLI line numbers fail, and app icon resources are packaged without SwiftPM warnings.
- The editable preview slice keeps source metadata read-only, derives the exact Markdown from `CodexTaskDraft.markdown()`, and refreshes the suggested slug path when the title changes while preserving the preview date.
- Markdown stays the source of truth. Tasks are a projection, rollover dedup is derived from Today's Markdown, and SQLite rollover rows are audit state.
- Codex task files use `specs/tasks/yyyy-mm-dd-title-slug.md` with numeric suffixes for collisions. Source notes are not modified by the M4 slices so far.
- Context bundle files use `artifacts/context-bundles/yyyy-mm-dd-title-slug-context.md` with numeric suffixes for collisions. Source notes and task files are not modified by bundle creation.
- The in-app bundle preview is derived from the exact draft and relative path that were approved for task-file creation. Editing the task draft or starting a fresh task preview clears the bundle offer until another task file is approved.
- Source-note backlinking remains parked because task files and context bundles already carry source provenance without source-note mutation.
- Milestone 5 has a first Dynamic Blocks slice: `/daymark open-loops` commands stay visible in Markdown, `daymark blocks refresh --source <path>` previews the generated region, and `--apply` writes one idempotent generated region below the command.
- Milestone 5 also has `/daymark source-list #tag`: it scans local Markdown sources, strips generated regions before matching, ignores `/daymark ...` command lines for tag matching, and renders title plus relative path in deterministic order.
- Milestone 5 also has `/daymark codex-context #tag`: it scans existing local task specs and context bundles, strips generated regions before matching, inherits tags through referenced source notes or task specs, and renders compact task and source path references without copying large excerpts.
- Milestone 5 also has `/daymark weekly-review`: it renders a compact local review scaffold with current open loops, completed tasks from the anchored week, recent Codex handoff artifacts, and source notes referenced by those handoffs.
- Dynamic block generated regions use `<!-- daymark:block-begin <hash> -->` and `<!-- daymark:block-end <hash> -->` markers. Task scans strip those regions before parsing tasks so generated checklist lines do not feed back into Open Loops.
- Dynamic block apply records rebuildable metadata in `.daymark/dynamic-blocks.json`. Dry-run writes no cache. Cache deletion or corruption does not affect Markdown correctness, and duplicate cache records no longer crash apply.
- After the 2026-06-29 hardening pass: `blocks refresh --source` is workspace-confined; region stripping and replacement are complete-pair and hash-aware (a stray begin marker no longer hides following tasks); `apply` preserves CRLF; fence matching (shared `MarkdownFenceScanner`) respects fence type and length.
- `DailyMarkdownProjectionReader` (DaymarkIndexer) is the single daily-Markdown projection path used by both the indexer and the CLI. `rebuild` prunes projections for deleted daily notes. `daymark open-loops` reads fresh from Markdown without a prior `rebuild`.
- Note projection is atomic: `Database.replaceNoteProjection` and `deleteNote` each run in one transaction.
- The Codex task-file parser lives in `DaymarkCore` (`CodexTaskDraft.parse`) beside the writer and is fence-aware; excerpt fences widen to wrap any backtick content. `AppState` holds one `CreatedCodexTask`, and view button state uses `CodexTaskDraft.isWritable` / `CodexContextBundle.isWritable`.
- App refresh remains the main M5 follow-up after the CLI/domain renderer set.
- The default workspace root is `~/phoenix`; ADR-005 is reversed.
- Do not add Gmail, Calendar, AI, cloud sync, embeddings, Codex execution, app-bundle work, or global hotkey work while starting Milestone 5.

### Required Checks

- `git status --short`
- `swift test --skip CommandTests` for the library tests. Run the CLI command tests from the prebuilt bundle, not `swift test --filter`: build the test bundle (`swift build --build-tests`), then build the CLI LAST (`swift build --product daymark`) so it wins the `Daymark`/`daymark` case-insensitive collision, then `xcrun xctest .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest` with no build in between. If a CLI test hangs to its timeout, the spawned binary is the GUI app, not the CLI; rebuild `daymark` last and re-run.
- `swift build --product daymark` and `swift build --product Daymark`.
- Temp-workspace Dynamic Blocks check: create prior and current daily notes, add a tagged project note, add a task spec and context bundle referencing that source, put `/daymark open-loops`, `/daymark source-list #tag`, `/daymark codex-context #tag`, and `/daymark weekly-review` in the current note, run dry-run and confirm no note or cache write, run apply and confirm one marker pair per command plus `.daymark/dynamic-blocks.json`, run repeat apply and confirm no duplicate output, edit text outside generated regions and confirm it is preserved, inject a generated checkbox inside a region and confirm it does not feed back through rebuild/open-loops/weekly-review, delete `.daymark`, and confirm refresh remains idempotent and recreates cache metadata.
- `daymark doctor` (read-only).
