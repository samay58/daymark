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
