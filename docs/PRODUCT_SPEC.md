# Product Spec

## Daymark One-Page North Star

Daymark is a high-craft native macOS workspace centered on today's Markdown note.

It should feel like a quiet Apple Notes-style notebook with the speed and translucency of Antinote and SideNotes, the intelligent daily-note behavior of Char, the dynamic-document substrate of Embark, and the interaction craft bar of Rauno Freiberg, Emil Kowalski, and Devouring Details.

Default workspace: `~/phoenix`

Human source of truth: Markdown files

Operational index: SQLite in `~/phoenix/.daymark`

Primary surfaces:

1. Today
2. Slip
3. Command palette
4. Open Loops
5. Codex Task Composer

Core loop:

```txt
Capture -> write -> parse -> link -> roll forward -> hand off to Codex -> review
```

Quality bar:

- Typing is sacred.
- Today is home.
- Capture opens in under 100 ms.
- Cold launch to editable Today is under 1.2 s.
- Keystroke latency is under 16 ms.
- Search first result is under 120 ms.
- No network is required for v0.
- No AI is required for v0.
- No dashboard.
- No chatbot-first UI.
- No cloud sync.
- No red badges.
- No hidden proprietary note format.

Stack:

- SwiftUI shell
- AppKit `NSTextView` editor
- SQLite local index
- Markdown in `~/phoenix`
- Swift concurrency
- Native file watching
- Swift CLI

Top percentile great:

The app is beautiful empty, fast under load, native in feel, useful without AI, trustworthy with files, and precise enough that messy notes can become Codex-ready specs without extra explanation.

## Product Identity

Daymark is a quiet native Mac workspace for notes, context, and next actions.

The name suggests a visible navigational marker: orientation, daily rhythm, continuity, and calm direction.

Product name: Daymark

App bundle/display name: Daymark

CLI: `daymark`

Internal metadata folder: `.daymark`

Workspace root: `~/phoenix`

## Primary User

The first version optimizes for one high-context operator moving across meetings, email, calendar, memos, deal notes, local files, code agents, browser research, personal planning, and daily open loops.

That means fast over collaborative, local over cloud, craft over breadth, daily use over demos, plain files over proprietary storage, and Codex handoff over generic AI chat.

## Product Surfaces

### Today

Today is the home surface. The app opens directly to the daily Markdown note. The editor is the product center.

### Slip

Slip is a temporary scratch surface that opens from anywhere. It is not Today, not Inbox, and not a permanent junk drawer. Slip captures can be discarded, appended to Today, converted to a task, moved to a note, or converted to a Codex task.

### Command Palette

The command palette navigates, searches, converts, and runs local commands. It should feel closer to Spotlight than a SaaS command menu.

### Open Loops

Open Loops is a trust surface, not a traditional todo list. It tracks commitments, waiting items, rollovers, and Codex task candidates with source visibility.

### Codex Task Composer

The composer turns selected messy notes into a previewed implementation spec. No task file is written without approval.

## Workspace Structure

```txt
~/phoenix/
  daily/
  slip/
  inbox/
  projects/
  deals/
  people/
  meetings/
  specs/
    tasks/
  artifacts/
    attachments/
    exports/
    context-bundles/
  .daymark/
    daymark.db
    dynamic-blocks.json   (rebuildable render metadata, created on first apply)
    indexes/
    migrations/
```

Human-readable content lives outside `.daymark`. Machine state lives inside `.daymark`. No credentials are stored in `~/phoenix`.

## Daily Note Shape

```md
# Monday, June 22

## Brief

- 10:30 Acme founder call
- Rolled over: Send Sarah updated model assumptions
- Suggested focus: finish Acme memo before starting new research threads

## Capture

- Sarah mentioned buyer expansion may shift model assumptions.
- [ ] Ask Sarah for updated model assumptions #deal/acme @sarah due:today

## Decisions

- Markdown remains the human-readable source of truth.
- SQLite is the operational index, not the authoring format.

## End of day

Still open:
- [ ] Review Acme memo before IC
```
