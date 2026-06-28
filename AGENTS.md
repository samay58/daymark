# AGENTS.md

## Product

We are building Daymark, a high-craft native macOS workspace centered on a daily Markdown note.

Daymark stores readable files in `~/phoenix`, indexes them locally with SQLite, and helps turn notes into tasks, open loops, dynamic blocks, meeting prep, and Codex-ready implementation specs.

## North Star

Build the calmest, fastest, most beautiful local-first daily workspace for thinking, capturing, planning, and handing precise work to Codex.

## Current Product Principles

1. Writing is sacred.
2. The app opens to Today.
3. `~/phoenix` is the durable workspace.
4. Markdown is the human-readable source of truth.
5. SQLite is the local operational index.
6. AI is optional and appears in the margins.
7. Every external action requires preview and approval.
8. High-frequency interactions must be nearly instant.
9. No dashboard home screen.
10. No chatbot-first UI.

## Mandatory Context Files

Before making product or architecture changes, read:

- `docs/PRODUCT_SPEC.md`
- `docs/ROADMAP.md`
- `docs/QUALITY_BAR.md`
- `docs/ARCHITECTURE.md`
- `docs/NON_GOALS.md`
- `docs/ACCEPTANCE_CRITERIA.md`

Before making UI, motion, or interaction changes, also read:

- `docs/DESIGN_SYSTEM.md`
- `docs/INTERACTION_SPEC.md`
- `reference/mockups/`
- `reference/cold-start-craft/`

## Work Session Protocol

At the start of each task, state:

- Current milestone
- Target outcome
- Files likely to change
- Non-goals
- Acceptance criteria
- Tests or checks to run
- Risks

At the end of each task, state:

- What changed
- Why it moves Daymark closer to the spec
- What acceptance criteria now pass
- What tests or checks were run
- Remaining work
- Any deviations from the spec
- Any architectural decisions that require approval

## Scope Control

Do not add new product surfaces, integrations, dependencies, or architectural patterns unless the task explicitly asks for them or you add a decision record in `docs/DECISIONS.md`.

If a change seems useful but is outside the current milestone, add it to `docs/PARKING_LOT.md` instead of implementing it.

Work on exactly one active milestone per session.

## Technical Stack

Default stack:

- SwiftUI for app shell
- AppKit `NSTextView` wrapper for editor
- SQLite for local index
- Markdown files in `~/phoenix`
- Swift concurrency for indexing
- Native file watching
- Swift CLI named `daymark`

Do not switch to Tauri, Electron, React, CloudKit, Core Data, or a web editor without a decision record and explicit approval.

## Quality Bar

Daymark is not good enough if:

- Typing feels laggy.
- Capture takes over one second.
- The app feels like a web dashboard.
- The editor feels non-native.
- The sidebar is noisy.
- Generated files are not human-readable.
- A feature works but does not improve the core loop.

## Testing

Run relevant tests after code changes.

Add tests for:

- Markdown parsing
- Task parsing
- Rollover idempotency
- SQLite migrations
- File watcher behavior
- Codex task file generation

## Design

Follow `docs/DESIGN_SYSTEM.md` and `docs/INTERACTION_SPEC.md`.

High-frequency keyboard surfaces should be almost instant. Do not add decorative animation to command palette or capture. Do not use red badges, colorful icon clutter, chatbot bubbles, or AI sparkle motifs.

## Performance

Respect `docs/PERFORMANCE_BUDGETS.md`.

Typing must never wait on indexing, SQLite, AI, network, Calendar, Gmail, or Codex.

## Non-goals

Respect `docs/NON_GOALS.md`. When tempted to add a feature outside the current milestone, stop.
