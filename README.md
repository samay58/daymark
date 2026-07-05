# Daymark

Daymark is a high-craft, local-first macOS workspace centered on today's Markdown note. Markdown files in `~/phoenix` are the source of truth; a local SQLite index under `~/phoenix/.daymark/` is a rebuildable projection. The app opens to Today, captures fast, and keeps everything as readable Markdown.

## Status

Milestones 0 (taste prototype), 1 (local workspace), 2 (Slip and capture), 3 (Tasks and Open Loops), 4 (Codex Handoff), and 5 (Dynamic Blocks) are complete. Milestone 7 (Dynamic Note Surface) has shipped: Today is a single-pane, note-centric surface. The sidebar and the right-margin panel are gone. The live editor renders clickable checkboxes, tag and wikilink pills, and due-date pills over the literal Markdown buffer, and conceals rollover and provenance markup until the caret touches it. Dynamic-block generated regions render as interactive cards inline in the note, with refresh, preview, apply, and view-source states. The Codex composer is a popover anchored at the selection, and an approved task file produces a receipt card with Finder reveal, path copy, and context-bundle creation. The day header is a material chrome band over the writing canvas. The Phase 4 visual and motion polish pass is still in progress. Milestone 6 (meeting prep) is paused after its first CLI/domain slice; the app meeting picker resumes after Milestone 7 closes. See `docs/PROGRESS.md` for the current state and `docs/ROADMAP.md` for the plan.

## Build and run

```bash
swift build                 # build all targets
swift test                  # run the test suite
swift run Daymark           # launch the SwiftUI app (opens to Today)
swift run daymark doctor    # read-only workspace and index health check
```

The package builds two executables whose names differ only by case: the app `Daymark` and the CLI `daymark`. On a case-insensitive filesystem (macOS default) they share one path in `.build/`, so build or run one product at a time. `swift run Daymark` and `swift run daymark <command>` each relink the right one.

## Capture from the CLI

```bash
daymark capture "a quick thought"           # append to this month's slip/YYYY-MM.md
daymark capture --today "goes under Today"  # append under today's ## Capture
daymark capture --task "do this"            # append an open task line
echo "piped text" | daymark capture         # read from stdin
```

## CLI commands

`doctor`, `init`, `index`, `rebuild`, `capture`, `rollover`, `end-of-day`, `open-loops`, `codex-task`, `context-bundle`, `blocks`, `meeting-prep`, `search`, `today`. Run `swift run daymark` for full usage. Pass `--root <path>` or set `DAYMARK_WORKSPACE_ROOT` to point at a workspace other than `~/phoenix`.

```bash
daymark rebuild                    # project every daily note into the index
daymark rollover --apply           # roll prior open tasks into Today's Brief
daymark end-of-day                 # list today's still-open tasks, read-only
daymark open-loops                 # list open tasks, grouped, read-only
daymark codex-task --source daily/2026/06/2026-06-29.md --line 12
daymark codex-task --source daily/2026/06/2026-06-29.md --line 12 --apply
daymark context-bundle --task specs/tasks/2026-06-29-example.md
daymark context-bundle --task specs/tasks/2026-06-29-example.md --apply
daymark blocks refresh --source daily/2026/06/2026-06-29.md
daymark blocks refresh --source daily/2026/06/2026-06-29.md --apply
daymark meeting-prep --event-file /tmp/event.json
daymark meeting-prep --event-file /tmp/event.json --apply
# In a note, write: /daymark source-list #project/daymark
# Then preview or apply with the same blocks refresh command.
# In a note, write: /daymark codex-context #project/daymark
# Then preview or apply to list existing matching task specs and context bundles.
# In a note, write: /daymark weekly-review
# Then preview or apply to insert a compact local weekly scaffold.
```

In the app, use `Refresh Dynamic Blocks` from the Daymark menu, the command palette, or a card's own refresh button when Today's note contains a visible `/daymark ...` command. Each generated region renders as an inline card; refresh previews the incoming Markdown on the card and writes only after Apply.

## Layout

- `Daymark/`: SwiftUI app shell and AppKit editor.
- `Sources/`: shared libraries (`DaymarkCore`, `DaymarkStore`, `DaymarkIndexer`, `DaymarkAgents`) and the `daymark` CLI.
- `Tests/`: the SwiftPM test suite.
- `docs/`: product spec, roadmap, architecture, decisions, and progress.
- `reference/mockups/` and `reference/cold-start-craft/`: design references.
