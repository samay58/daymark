# Roadmap

Status markers reflect what is built. `docs/PROGRESS.md` holds the detailed log.

## Governance and Scaffold (Done)

Goal: create durable instructions, docs, module boundaries, tests, and a native Swift structure before product features begin.

Build:

- `AGENTS.md`
- Governance docs
- Swift package scaffold
- SwiftUI app shell
- AppKit editor wrapper
- Local-first core/store/indexer module boundaries
- CLI target named `daymark`
- Starter tests and scripts

Acceptance:

- `swift build` succeeds.
- `swift test` succeeds.
- The docs explain the north star, milestones, stack, non-goals, and review gates.
- Product mockups and craft references are saved in the repo.

## Milestone 0: Taste Prototype (Done)

Goal: prove the app feels gorgeous before building intelligence.

Build:

- SwiftUI macOS app shell
- Native translucent sidebar
- Today editor mock
- Slip panel mock
- Command palette mock
- Sample suggestion card
- Sample Codex task composer
- Light mode token pass
- Dark mode token support
- Motion constants

Acceptance:

- The app looks beautiful with fake data.
- The typing area feels calm.
- Slip opens instantly.
- Command palette feels native and fast.
- No AI is needed.
- The user would want to leave it open all day.

Non-goals:

- No real indexing
- No real Codex integration
- No Gmail
- No Calendar
- No cloud
- No embeddings

## Milestone 1: Local Workspace (Done)

Goal: Daymark can be used as a real daily note app for one full day.

Build:

- Initialize `~/phoenix`
- Create daily note
- Open Today on launch
- Autosave Markdown
- Atomic file writes
- File watcher
- SQLite notes and blocks tables
- Basic FTS search
- Settings for workspace root

## Milestone 2: Slip and Capture (Done; system-global hotkey deferred)

Goal: capture from anywhere faster than Apple Notes.

Done: floating Slip panel, temporary captures to a monthly Slip file, append to Today, discard, promote to task, an in-app Option+Space (focused), and a `daymark capture` CLI as the scriptable capture-from-anywhere path. Deferred: the true system-global hotkey and menu bar helper, which need a signed app bundle (gated by an ADR). Selected-text capture is not built.

## Milestone 3: Tasks and Open Loops (Done)

Goal: Daymark reliably tracks unfinished commitments.

Build task parser, completion, due dates, recurrence, rollover, Open Loops, and end-of-day review.

Done: the task model and parser (status, tags, mentions, due tokens, source metadata, fenced-code awareness), a rebuildable `tasks` projection in SQLite (migration `003_tasks.sql`), read-only Open Loops through `daymark open-loops`, automatic task rollover with Markdown-derived dedup markers plus `004_rollovers.sql`, read-only `daymark end-of-day`, and an in-app read-only Open Loops surface. Recurrence is parked because it is not in the Milestone 3 acceptance criteria.

## Milestone 4: Codex Handoff (Done)

Goal: messy notes become crisp implementation specs.

Why this matters: Daymark should turn daily-note fragments into work another agent can execute without Samay re-explaining the context. This milestone is about precise handoff files, not running Codex.

Build:

- Select current highlighted text or, when no selection exists, the current Markdown block.
- Derive a `CodexTaskDraft` with title, goal, source, constraints, acceptance criteria, and suggested file path.
- Render the draft in the existing right-side Codex Task Composer as an editable preview.
- Write exactly one approved Markdown task file under `specs/tasks/`.
- Include stable source provenance with the source note path and line or block identity.
- Keep source-note backlinking parked unless it is built later as a separate approved, idempotent write.
- Add a CLI path for dry-run and apply, so the feature can be tested against temp workspaces without launching the app.
- Add previewed context bundle export after draft generation and file write are solid.

First slice done:

- `CodexTaskDraft` now writes plain Markdown with source path, line or block, excerpt, constraints, acceptance criteria, and suggested file path.
- `SourceSelector` extracts selected text or the current Markdown block with line metadata, and rejects empty heading-only sections.
- `PreviewBuilder` creates deterministic drafts and collision-safe suggested paths.
- `CodexTaskFileWriter` writes one approved file under `specs/tasks/` without modifying the source note.
- `daymark codex-task` supports dry-run preview and `--apply`.
- Command Shift C in the app opens a real preview in the Codex Task Composer, and `Create Task File` writes only after approval.

Editable preview slice done:

- The in-app composer lets the user edit title, goal, constraints, and acceptance criteria before approval.
- Source path, source line or block, source excerpt, and the target file path remain read-only.
- The Markdown preview is still derived from `CodexTaskDraft.markdown()`.
- Title edits refresh the date-prefixed slug path without reading the filesystem on every keystroke.

Context bundle CLI slice done:

- `CodexContextBundle` writes a readable single-file Markdown bundle with task path, goal, source path, source excerpt, constraints, and acceptance criteria.
- `CodexContextBundleWriter` writes under `artifacts/context-bundles/` with numeric suffixes and does not modify the source note or task file.
- `daymark context-bundle --task ...` supports dry-run preview and `--apply`.

In-app context bundle slice done:

- After a task file is created in the Codex Task Composer, Daymark offers a compact context bundle preview.
- The bundle preview shows the exact Markdown from `CodexContextBundle.markdown()` and the read-only target path.
- `Create Context Bundle` writes one approved file under `artifacts/context-bundles/` and does not modify the source note or task file.

Closeout done:

- A real app pass confirmed the Codex Task Composer opens with editable draft fields and read-only source metadata. Domain tests cover selected text and current-block extraction.
- Starting a fresh task preview clears any stale created-task receipt or bundle preview.
- Source-note backlinking remains parked because task files and context bundles already carry enough source provenance for handoff without mutating notes.

Non-goals:

- No automatic Codex execution.
- No network or model call.
- No multi-file writes without preview.
- No Gmail, Calendar, dynamic blocks, app bundle, or global hotkey work.

Acceptance:

- Selected text or current block can generate a readable task draft.
- The preview shows the exact Markdown that will be written.
- Nothing is written until approval.
- Approved files land in `specs/tasks/` with collision-safe names.
- Context bundles land in `artifacts/context-bundles/` with collision-safe names after separate approval.
- A fresh agent can work from the generated file without hidden app state.

## Milestone 5: Dynamic Blocks

Goal: notes become dynamic without becoming dashboards.

Why this matters: useful computed context should sit beside the source Markdown without replacing it. Dynamic blocks are local views, not a dashboard layer.

Status: ready to close. The CLI/domain slices are done for `/daymark open-loops`, `/daymark source-list #tag`, `/daymark codex-context #tag`, and `/daymark weekly-review`: Daymark parses visible commands, renders deterministic local Markdown from the workspace, previews the generated region, applies it idempotently only when `--apply` is passed, and records rebuildable `.daymark` render metadata on apply. The app can preview the same refresh plan for Today's note in the right margin and applies it only after approval.

Build:

- Parse `/daymark ...` block commands from Markdown. Done for `open-loops`, `source-list`, `codex-context`, and `weekly-review`, including tag arguments where supported and fenced-code awareness.
- Support conservative local commands first: `open-loops`, `source-list`, `codex-context`, and `weekly-review`. The CLI/domain renderers are implemented.
- Cache rendered output metadata in `.daymark` as rebuildable state. Done for approved CLI apply; Markdown remains authoritative.
- Show patch previews before writing rendered output back into notes. Done for CLI dry-run and the in-app right-margin approval surface.
- Keep the source command visible and readable. The implemented renderers keep `/daymark open-loops`, `/daymark source-list #tag`, `/daymark codex-context #tag`, and `/daymark weekly-review` in the note and insert generated output in a marked region below the command.
- Add a CLI refresh command before adding automatic app refresh. Done with `daymark blocks refresh --source <path>` / `--apply`, plus explicit in-app preview and approval. Automatic refresh remains out of scope.

Non-goals:

- No hidden live widgets that only make sense inside Daymark.
- No destructive overwrite of surrounding user text.
- No AI-generated summaries in this milestone.
- No Calendar or Gmail backed blocks until their own milestones.

Acceptance:

- Blocks render deterministic local output.
- Refresh can be repeated without duplicate generated content.
- User edits outside the generated region are preserved.
- Deleting `.daymark` and rebuilding does not destroy note meaning.

## Milestone 6: Calendar and Meeting Prep

Goal: Daymark helps prep meetings using local notes plus calendar metadata.

Why this matters: meeting prep should reduce context switching by connecting a calendar event to relevant notes, people, prior decisions, and open loops. It must stay permissioned and local-first.

Build:

- Add a calendar metadata adapter behind explicit setup.
- In v0, prefer local calendar reads or imported event snapshots over account-server coupling.
- Link events to notes by date, attendees, project tags, and meeting-note paths.
- Generate a read-only prep view with relevant notes, tasks, and unresolved questions.
- Add a clean Markdown export under `meetings/` only after preview.
- Keep Today editable before and during prep loading.

Non-goals:

- No background network reads by default.
- No automatic meeting notes without approval.
- No joining calls, recording calls, or transcribing audio.

Acceptance:

- A meeting can be selected and matched to local context.
- Prep output cites the source files it used.
- Exported prep is readable Markdown.
- Failure to read calendar data never blocks Today or typing.

## Milestone 7: Gmail Draft Preview

Goal: follow-up tasks can become draft emails with visible sources.

Why this matters: follow-up has high value, but is unsafe if it becomes invisible automation. Daymark should produce source-grounded drafts that Samay can edit, copy, or approve elsewhere.

Build:

- Start from a task, note selection, or meeting prep artifact.
- Gather only explicit local context and approved message metadata.
- Generate a draft preview with cited source snippets and editable fields.
- Keep generated text out of the source note unless explicitly inserted.
- Provide a copy/export path before any mail-client write path.

Non-goals:

- No sending.
- No auto-archiving, labeling, or modifying mailbox state.
- No credential storage in `~/phoenix`.
- No relationship or tone inference beyond the provided sources.

Acceptance:

- A follow-up task can produce an editable draft preview.
- Every substantive claim in the draft points back to a source.
- The user can copy or discard the draft without side effects.
- Any future mail-client write requires a separate explicit approval step.

## Milestone 8: iOS Capture Companion

Goal: capture and review on iPhone.

Why this matters: capture has to follow the user away from the Mac, but the phone app should be a companion, not a second workspace.

Build:

- Fast capture into the same plain Markdown workspace.
- Review recent captures and today's open loops.
- Resolve conflicts without losing text.
- Keep the phone surface small: capture, review, and send-to-Today.
- Reuse Swift domain logic where possible.

Non-goals:

- No full mobile clone of the Mac app.
- No chat UI.
- No proprietary sync format.
- No starting this before the Mac workflow is genuinely useful.

Acceptance:

- Phone capture arrives as readable Markdown.
- Offline captures are queued and reconciled safely.
- The Mac remains the primary authoring and planning surface.
- The iOS companion can be removed without corrupting the workspace.
