# Decision Log

## ADR-001: Use SwiftUI Shell With AppKit Editor

Status: Accepted
Date: 2026-06-28

### Context

Daymark needs to feel like a high-craft native Mac notes app. The editor is the highest-risk part.

### Decision

Use SwiftUI for the app shell and AppKit `NSTextView` for the editor.

### Why

SwiftUI gives native platform structure and a future iOS path. AppKit gives mature text behavior.

### Alternatives Considered

- Pure SwiftUI `TextEditor`
- Tauri with web editor
- Electron with ProseMirror
- Full AppKit app

### Risks

`NSTextView` Markdown overlays may be complex.

### Reversal Trigger

If by Milestone 0 the editor cannot support the required typing feel and Markdown rendering, evaluate TextKit 2 or deeper AppKit editor approaches.

## ADR-002: Start Package-First, Preserve App-Bundle Decision Point

Status: Accepted
Date: 2026-06-28

### Context

The first task is repository governance and scaffold, not shipping an app bundle.

### Decision

Start with a SwiftPM package that builds the app shell, shared modules, tests, and future CLI. Add an Xcode app project during Milestone 0 if app-bundle behavior, signing, UI tests, global hotkeys, or menu bar helper work require it.

### Why

SwiftPM makes the scaffold reproducible immediately with `swift build`, `swift test`, and `swift run daymark doctor`.

### Risks

A SwiftPM app target is not a full signed macOS app bundle.

### Reversal Trigger

Milestone 0 requires native app lifecycle behavior that SwiftPM cannot represent cleanly.

## ADR-003: Use Markdown as Source and SQLite as Index

Status: Accepted
Date: 2026-06-28

### Context

Daymark needs readable local files and fast operational projections.

### Decision

Markdown in `~/phoenix` is the source of truth. SQLite in `~/phoenix/.daymark` is the local index, event log, task projection, dynamic block cache, and search store.

### Risks

Files and database may diverge.

### Mitigation

Use content hashes, atomic writes, file watching, rebuildable indexes, migration tests, and a `daymark doctor` command.

## ADR-004: Use the system libsqlite3 via import SQLite3

Status: Accepted
Date: 2026-06-28

### Context

ADR-003 commits to SQLite as the local index. Milestone 1 needs a real connection. The scope rules and `docs/NON_GOALS.md` discourage new dependencies.

### Decision

Link the system `libsqlite3` through Swift's `import SQLite3` module. No SwiftPM SQLite wrapper such as GRDB or SQLite.swift. The `Database` actor owns the C API directly with prepared statements, WAL, and foreign keys.

### Risks

The C API is verbose and unsafe if misused. There is no compile-time query checking.

### Mitigation

Confine all C calls to the `Database` actor behind a small typed surface. Cover open, migrate, upsert, replace, and rebuild with tests. Migrations run in a transaction and are idempotent.

## ADR-005: Default workspace root (reversed)

Status: Reversed on 2026-06-28 by the user. The default is `~/phoenix`, matching the spec.
Date: 2026-06-28

### Context

The user's `~/phoenix` is a large existing knowledge vault (01-active through 04-knowledge-base). Daymark's bootstrap creates its own top-level directories (daily, slip, inbox, projects, deals, people, meetings, specs, artifacts, .daymark). The first decision defaulted to a dedicated `~/Daymark` folder to avoid adding those to the vault.

### Reversal

The user reversed this: the default workspace root is `~/phoenix`, because operating directly on the vault is the point of the product. `WorkspaceRoot.defaultWorkspace` is `~/phoenix`. Bootstrap remains additive, so it only adds the Daymark directories it does not already find and never removes or overwrites existing vault content. Resolution precedence is unchanged: an explicit override and `DAYMARK_WORKSPACE_ROOT` still win, and Settings can point the workspace at any folder. The spec's `~/phoenix` default stands.

## ADR-006: Rollover Dedup Marker in Markdown

Status: Accepted
Date: 2026-06-28

### Context

Milestone 3 needs automatic rollover of incomplete tasks from prior daily notes into Today. SQLite is rebuildable, so duplicate prevention cannot rely only on a database row. If `daymark.db` is deleted and rebuilt from Markdown, running rollover again must not add a second copy of the same source task.

### Decision

Each rolled task is written as a normal Brief bullet with a hidden HTML comment marker:

```md
- Rolled over: Send Sarah updated model assumptions (from daily/2026/06/2026-06-27.md:5) <!-- daymark-rollover:<sha256> -->
```

The hash is SHA-256 of the task source key: source note path, source line number, and original Markdown task line. Rollover checks Today's Markdown for that marker before writing. SQLite also records the rollover in a `rollovers` table, but that row is an audit and fast lookup record, not the source of truth.

### Why

The visible line stays readable in any Markdown editor. The marker is hidden in rendered Markdown and durable in source Markdown, so idempotency survives a full database rebuild.

### Risks

If a user manually deletes the marker but leaves the rolled bullet, Daymark can no longer prove the source task has already rolled forward and may add it again.

### Mitigation

Keep the marker on the same line as the rolled bullet so manual edits are less likely to separate it from the readable text. The `rollovers` table still records normal app-driven rollovers for auditability.

## ADR-007: Codex Task File Naming and Source Links

Status: Accepted
Date: 2026-06-29

### Context

Milestone 4 writes handoff files that another agent can execute. These files must be readable outside Daymark, must not rely on SQLite, and must never overwrite an existing task file.

### Decision

Approved Codex task files are written under `specs/tasks/` with a date prefix and a slug derived from the draft title:

```txt
specs/tasks/2026-06-29-make-rollover-deterministic.md
specs/tasks/2026-06-29-make-rollover-deterministic-2.md
```

The generated Markdown includes the source note path, source line or line range when known, the source block heading when known, and the selected excerpt. Heading-only selections and empty sections are rejected rather than turned into task files. The source note is not modified by this slice.

### Why

The path is stable, readable, and sortable. The numeric suffix prevents overwrites while still making repeated attempts easy to inspect. Keeping the source link in the task file preserves provenance without adding hidden app state or source-note mutations.

### Risks

Two repeated approvals can create two task files for the same note excerpt.

### Mitigation

The suffix makes the duplicate visible and non-destructive. Future backlinking or task indexes can add stronger duplicate detection after the basic preview and approval flow has real usage.
