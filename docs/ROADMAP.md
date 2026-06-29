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

## Milestone 3: Tasks and Open Loops (In progress)

Goal: Daymark reliably tracks unfinished commitments.

Build task parser, completion, due dates, recurrence, rollover, Open Loops, and end-of-day review.

Done: the task model and parser (status, tags, mentions, due tokens, source metadata, fenced-code awareness), a rebuildable `tasks` projection in SQLite (migration `003_tasks.sql`), and a read-only Open Loops query surfaced through `daymark open-loops`. Next: task rollover as its own slice, then recurrence, end-of-day review, and an in-app Open Loops surface.

## Milestone 4: Codex Handoff

Goal: messy notes become crisp implementation specs.

Build selection to Codex task, preview composer, spec template, acceptance criteria generator, source backlink, context bundle export, and CLI commands.

## Milestone 5: Dynamic Blocks

Goal: notes become dynamic without becoming dashboards.

Build fixed local blocks for open loops, today calendar, source list, and Codex context.

## Milestone 6: Calendar and Meeting Prep

Goal: Daymark helps prep meetings using local notes plus calendar metadata.

Do this only after local workspace, tasks, and Codex handoff are trustworthy.

## Milestone 7: Gmail Draft Preview

Goal: follow-up tasks can become draft emails with visible sources.

Nothing sends automatically.

## Milestone 8: iOS Capture Companion

Goal: capture and review on iPhone.

Do not start here. Mac quality comes first.
