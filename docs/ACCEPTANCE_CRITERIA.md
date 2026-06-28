# Acceptance Criteria

## Hard Invariants

- Today opens before indexing completes.
- Typing never waits on indexing, SQLite, AI, network, Calendar, Gmail, or Codex.
- Markdown remains readable outside Daymark.
- SQLite can be rebuilt from files.
- Generated actions are previewed before execution.
- No network or account is required in v0.

## Governance and Scaffold

- Required governance files exist.
- Swift package builds.
- Starter tests pass.
- Mockups are saved under `reference/mockups/`.
- Craft references are saved under `reference/cold-start-craft/`.
- Future sessions have a clear `AGENTS.md` protocol.

## Milestone 0: Taste Prototype

- The app looks beautiful with fake data.
- The typing area feels calm.
- Slip opens instantly.
- Command palette feels native and fast.
- No AI is needed.
- The app feels worth leaving open all day.

## Milestone 1: Local Workspace

- Today note persists as Markdown.
- External edits from terminal or Codex appear.
- Search works locally.
- No network is required.
- No data loss.

## Milestone 2: Slip and Capture

- Global capture opens in under 100 ms.
- Typing focus is immediate.
- Enter saves.
- Captured text is retrievable.
- Temporary notes do not clutter Today unless promoted.

## Milestone 3: Tasks and Open Loops

- Incomplete tasks from yesterday roll forward.
- Completed tasks do not appear in Open Loops.
- Duplicate rollovers are prevented.
- Daily note remains clean Markdown.

## Milestone 4: Codex Handoff

- Selected text can generate a structured task file.
- Generated file lands in `~/phoenix/specs/tasks`.
- Generated task links back to source note.
- Codex can work from the file without private app internals.

## Milestone 5: Dynamic Blocks

- Dynamic blocks render predictable local views.
- Blocks can be refreshed.
- Generated output is cached.
- Updates never destructively overwrite user edits.
