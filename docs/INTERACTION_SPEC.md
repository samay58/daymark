# Interaction Spec

## App Launch

On launch:

1. Resolve workspace root.
2. Create `~/phoenix` if missing.
3. Create today's note if missing.
4. Open Today immediately.
5. Render editor before indexing completes.
6. Start indexing in background.
7. Load task rollover and brief asynchronously.

The user can type before indexing is complete.

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

## Open Loops

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

## Codex Task Composer

Trigger: Command Shift C

Input: selected text or current block.

Output: a preview card before file creation.

Rules:

- No auto-running Codex in v0.
- No creating more than one spec file without approval.
- No modifying source note except adding an explicit backlink if approved.

## Dynamic Blocks

Syntax:

```md
/daymark open-loops
/daymark open-loops #deal/acme
/daymark prep-next-meeting
/daymark source-list #deal/acme
/daymark codex-context #project/daymark
/daymark weekly-review
```

Rules:

- The source Markdown remains visible and readable.
- Rendered output is cached.
- Regeneration never destructively overwrites user edits.
- Updates use patch preview.

## Motion Budgets

```txt
Hover feedback:        80 ms
Checkbox completion:   100 to 140 ms
Command palette open:  80 to 100 ms
Command palette close: 60 to 80 ms
Slip open:             90 to 120 ms
Popover open:          120 to 160 ms
Panel transition:      160 to 220 ms
Daily navigation:      under 140 ms
```

High-frequency keyboard surfaces use almost no animation. No daily-use animation should exceed 220 ms.
