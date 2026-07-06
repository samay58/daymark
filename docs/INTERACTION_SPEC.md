# Interaction Spec

This is a target design spec describing intended interactions. Not every surface listed here
is built yet. For what is implemented today, see `docs/ROADMAP.md` and the
`## WHERE WE LEFT OFF` block in `docs/PROGRESS.md`.

## Keyboard Map

```txt
Command 1:        Today
Command K:        Command palette
Option Space:     Capture slip (app focused)
Command Shift C:  Codex composer popover
Command Shift R:  Refresh dynamic blocks (preview all)
Command L:        Open Loops overlay
Command Return:   Toggle checkbox on the caret line
Escape:           Close topmost overlay or popover
```

## App Launch

On launch:

1. Resolve workspace root.
2. Create `~/phoenix` if missing.
3. Create today's note if missing.
4. Open Today immediately.
5. Render editor before indexing completes.
6. Start indexing in background.
7. Load task rollover and brief asynchronously.

The user can type before indexing is complete. The window never opens maximized: if the
restored frame covers 90 percent or more of the screen, it resets to the default size,
centered.

## Global Capture

Shortcut: Option Space

Behavior:

- Open Slip in under 100 ms.
- Focus text input immediately.
- Enter saves.
- Shift Enter creates newline.
- Command Enter appends to Today.
- Command Shift T converts to task.
- Command Shift C creates Codex task draft.
- Escape dismisses.

Panel copy: `Capture to Daymark`

Do not use productivity-coach copy.

## Command Palette

Shortcut: Command K

Commands:

- Open Today
- Open Yesterday
- Search Notes
- Show Open Loops
- Create Codex Task from Selection
- Append Selection to Today
- Prep Next Meeting
- Create Project Note
- Create Deal Note
- Move Selection to Note
- Run Weekly Review
- Open Workspace in Finder
- Run Doctor

Performance:

- Local command results under 50 ms.
- Search first result under 120 ms.
- No spinner for local results.

## Live Note Body

The buffer is always the literal Markdown on disk. Styling and controls are attribute-only
and drawn, never a second copy of the text.

- Checkboxes render as clickable drawn controls over the literal `[ ]` / `[x]`. Clicking one
  toggles it through the normal undoable text-edit path, so autosave and indexing run exactly
  as they would for typing. The pointer becomes a hand over the box.
- Command Return toggles the checkbox on the caret's line when that line is a task; otherwise
  it is a no-op.
- The caret or an active selection intersecting a checkbox or a due-date pill reveals the
  literal characters underneath; moving away re-conceals them. Rollover dedup markers and
  `(from path:line)` provenance parentheticals conceal and reveal the same way: literal on
  disk, invisible in render, revealed only when the caret or selection touches them.
- Tags and wikilinks render as pills. Clicking either opens the command palette prefilled with
  the tag or link name. URLs render underlined and open in the default browser on click.
- The `/daymark` command line itself renders quiet: monospaced, tertiary color, never accent or
  body weight.

## Open Loops

Presentation: a centered overlay, opened from Command L, the day header's brief strip, or the
command palette's "Open Loops" action. 560 px wide, up to 70 percent of the window height, with
a scrim behind it. Escape or clicking the scrim closes it.

Sections:

- Due today
- Waiting on me
- Waiting on others
- Rolled repeatedly
- No date
- Codex tasks

Actions:

- Space: quick preview
- Enter: open source
- Command Enter: mark done
- D: defer
- C: create Codex task
- R: make recurring

## Task Rollover

On opening Today:

1. Find incomplete tasks from prior daily notes.
2. Exclude completed tasks.
3. Exclude tasks already rolled into today.
4. Add references to Today's Brief or Rolled Over section.
5. Preserve original task in the original note.
6. Record rollover event in SQLite.
7. Never duplicate a rollover for the same source task.

## Codex Composer and Receipts

Trigger: Command Shift C, with a selection or the current block, or the palette action "Create
Codex Task from Selection".

Behavior: a popover anchored at the selection (or the caret) opens to a two-field fast path:
editable Title and Goal, a read-only source chip (path and line range), and Create/Cancel.
Constraints, Acceptance Criteria, the full source, and the Markdown preview sit behind a
collapsed Details disclosure. Command Return creates immediately from the fast path. The
collapsed form writes exactly the same task file the expanded form would: every field stays
prefilled and bound to the same draft whether or not Details is ever opened. Create writes the
task file and closes the popover; Cancel or Escape dismisses without writing. The approval gate
is unchanged: the two-field default means better defaults, not fewer approvals.

On create, a receipt card rises at the column's bottom-right: task title, relative path, and
the actions Reveal in Finder, Copy path, Create context bundle, Done. The receipt persists
until dismissed; it is app chrome, never note content. "Create context bundle" expands the
receipt into the bundle preview; Approve writes the bundle and the receipt updates with its
path.

Rules:

- No auto-running Codex in v0.
- No creating more than one spec file without approval.
- The source note is never modified.

## Dynamic Blocks

Syntax:

```md
/daymark open-loops
/daymark open-loops #deal/acme
/daymark source-list #deal/acme
/daymark codex-context #project/daymark
/daymark weekly-review
```

Presentation: a well-formed generated region renders as an inline card in place of its literal
text, at full column width, filled with the same canvas color as the note so it reads as part
of the page rather than a separate surface, bounded by a hairline border. The header shows a
small status dot (tertiary at rest, accent while a preview is pending, warning once a preview
has gone stale), the block title in sentence case (Open Loops, Sources, Codex Context, Weekly
Review, or Generated when no command line is adjacent), and, on hover only, a generated-time
label, a refresh button, and a view-source toggle. Card bodies strip rollover-dedup markers and
`(from path:line)` provenance parentheticals entirely, showing a humanized generated-at date
instead; nothing that looks like machine text renders inside a card.

States:

- Idle: header and body, no footer.
- Preview pending: refresh (the card's own button, Command Shift R, or the palette action)
  shows a one-line change summary and the incoming Markdown, with Apply and Cancel.
- Stale: if the note changes after preview, the summary reads "Note changed; preview again"
  and Apply disables.
- Source revealed: the card collapses to a thin header strip above the literal region text;
  the toggle re-collapses it, and caret entry into the region also reveals it. This switch is
  instant, not animated (see Motion Budgets).

Rules:

- The source Markdown (the `/daymark ...` command line) remains visible and readable.
- Rendered output is cached in `.daymark/dynamic-blocks.json`, keyed by command hash.
- Regeneration never destructively overwrites user edits outside the generated region markers.
- Refresh previews every affected card's patch at once; Apply on any card applies the whole
  note's patch set atomically. Selective per-card apply is parked.
- Malformed regions (unpaired markers, hash mismatch) render as literal text, never hidden.

## Motion Budgets

```txt
Hover feedback:        80 ms
Checkbox completion:   100 to 140 ms
Command palette open and close: about 90 ms
Slip open:             90 to 120 ms
Popover open:          120 to 160 ms
Card hover controls fade: about 120 ms ease-out
Card refresh acknowledgment (icon rotation): about 110 ms, instant under Reduce Motion
Panel transition:      160 to 220 ms
Daily navigation:      under 140 ms
```

High-frequency keyboard surfaces use almost no animation. No daily-use animation should exceed 220 ms. Reduce Motion degrades every animation in this table to a plain state swap.

Reveal and conceal of checkboxes, due-date pills, and machine text (rollover markers, `(from
path:line)` provenance) crossfade over about 110 ms instead of snapping; a due-date pill that
sits mid-line fills its concealed literal's footprint while it fades, so revealing it never
shifts the line. A dynamic-block card's preview state transitions over about 160 ms, and the
Codex popover's Details disclosure expands over about 180 ms. All of these degrade to an
instant state swap under Reduce Motion. One deliberate exception: a dynamic-block card's source
reveal and collapse is an instant state swap, not an animated height transition, in every case,
not just under Reduce Motion. An animated version reintroduced a ghost-glyph bug during the
Phase 4 walk, so it stays a known deferral rather than a finished item until that mechanism is
redone.
