# Roadmap

## Governance and Scaffold

Goal: create durable instructions, docs, module boundaries, tests, and a native Swift structure before product features begin.

Build:

- `AGENTS.md`
- Governance docs
- Swift package scaffold
- SwiftUI app shell placeholder
- AppKit editor wrapper placeholder
- Local-first core/store/indexer module boundaries
- Future CLI target named `daymark`
- Starter tests and scripts

Acceptance:

- `swift build` succeeds.
- `swift test` succeeds.
- The docs explain the north star, milestones, stack, non-goals, and review gates.
- Product mockups and craft references are saved in the repo.

## Milestone 0: Taste Prototype

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

## Milestone 1: Local Workspace

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

## Milestone 2: Slip and Capture

Goal: capture from anywhere faster than Apple Notes.

Build global hotkey, menu bar helper, floating Slip panel, temporary captures, append to Today, discard, promote to task, and selected-text capture where possible.

## Milestone 3: Tasks and Open Loops

Goal: Daymark reliably tracks unfinished commitments.

Build task parser, completion, due dates, recurrence, rollover, Open Loops, and end-of-day review.

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
