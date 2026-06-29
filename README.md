# Daymark

Daymark is a high-craft, local-first macOS workspace centered on today's Markdown note. Markdown files in `~/phoenix` are the source of truth; a local SQLite index under `~/phoenix/.daymark/` is a rebuildable projection. The app opens to Today, captures fast, and keeps everything as readable Markdown.

## Status

Milestones 0 (taste prototype), 1 (local workspace), and 2 (Slip and capture) are complete. The next milestone is 3 (Tasks and Open Loops). See `docs/PROGRESS.md` for the current state and `docs/ROADMAP.md` for the plan.

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

`doctor`, `init`, `index`, `rebuild`, `capture`, `search`, `today`. Run `swift run daymark` for full usage. Pass `--root <path>` or set `DAYMARK_WORKSPACE_ROOT` to point at a workspace other than `~/phoenix`.

## Layout

- `Daymark/`: SwiftUI app shell and AppKit editor.
- `Sources/`: shared libraries (`DaymarkCore`, `DaymarkStore`, `DaymarkIndexer`, `DaymarkAgents`) and the `daymark` CLI.
- `Tests/`: the SwiftPM test suite.
- `docs/`: product spec, roadmap, architecture, decisions, and progress.
- `reference/mockups/` and `reference/cold-start-craft/`: design references.
