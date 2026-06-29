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

## WHERE WE LEFT OFF

### Active Milestone

Milestone 4: Codex Handoff is active.

### Start Here Next

1. Build the next concrete M4 slice: editable in-app preview fields, still writing exactly one approved Markdown task file.
2. Add optional source-note backlinking only if it is separately approved and idempotent.
3. Keep context bundle export parked until the editable preview path is green.

### Current Truths

- Milestone 0 is complete.
- Milestone 1 is complete.
- Milestone 2 is closed. Capture is implemented and hardened: monthly Slip file, append to Today, promote to task, discard, and a `daymark capture` CLI. The system-global hotkey is deferred behind an app-bundle ADR.
- Milestone 3 is closed. Tasks are parsed with due and source metadata, projected into a rebuildable `tasks` table, rolled forward through a Markdown-derived dedup marker, and surfaced through CLI plus the in-app Open Loops view.
- Milestone 4 is active. The first slice is complete: selected text or current Markdown block to a previewed draft, with an approved single-file write under `specs/tasks/`.
- The first slice has been hardened after real testing: empty heading-only sections are rejected, generic goal text was removed, bad CLI line numbers fail, and app icon resources are packaged without SwiftPM warnings.
- Markdown stays the source of truth. Tasks are a projection, rollover dedup is derived from Today's Markdown, and SQLite rollover rows are audit state.
- Codex task files use `specs/tasks/yyyy-mm-dd-title-slug.md` with numeric suffixes for collisions. Source notes are not modified by the first M4 slice.
- The default workspace root is `~/phoenix`; ADR-005 is reversed.
- Do not add Gmail, Calendar, AI, cloud sync, embeddings, dynamic blocks, Codex execution, app-bundle work, or global hotkey work while finishing Milestone 4.

### Required Checks

- `git status --short`
- `swift test --skip CommandTests` for the library tests, then the CLI tests via the prebuilt bundle (see the build-collision caveat above).
- `swift build --product daymark` and `swift build --product Daymark`.
- Temp-workspace `daymark codex-task` dry-run, apply, repeat-apply, empty-heading rejection, invalid-line rejection, and source-note unchanged check.
- `daymark doctor` (read-only).
