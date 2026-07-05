# Parking Lot

Good ideas that are not part of the current milestone belong here.

## Later

- App-bundle Xcode project with signing and UI test scheme.
- Menu bar helper.
- Global hotkey implementation.
- Calendar connector.
- Gmail connector.
- Embeddings.
- Cloud sync.
- iOS capture companion.
- Arbitrary dynamic block plugin system.

## Milestone 1 follow-ups

- Vault coexistence: resolved. The default workspace is `~/phoenix`, because operating on the vault is the point. Bootstrap is additive and never touches the existing 01-active through 04-knowledge-base trees. ADR-005 was reversed to record this. `DAYMARK_WORKSPACE_ROOT` and the Settings field still override it.
- Git: initialized on 2026-06-28 with a `.gitignore` for build artifacts. Future parallel sessions should branch per worktree rather than share one tree.

## Milestone 2 follow-ups (known limitations, deferred by scope)

- Global hotkey from anywhere: still deferred. Needs a signed app bundle plus accessibility or Carbon hotkey registration. In-app Option+Space (focused) and the `daymark capture` CLI cover capture for now. Gate the real hotkey behind an app-bundle ADR before building it.
- Executable name collision: the app product `Daymark` and the CLI product `daymark` differ only by case, so on a case-insensitive filesystem (macOS default) they resolve to one file in `.build/debug/`; whichever links last wins. `swift run Daymark` and `swift run daymark` each work because they relink, but the two binaries cannot coexist as build artifacts. The app-bundle milestone (`Daymark.app/Contents/MacOS/Daymark`) resolves this. Until then, build a single product at a time when running directly.
- Capture vs concurrent external edits: `SlipStore.save` and `DailyNoteStore.appendCapture/appendTask` do a read-modify-write that is not transactional. The write itself is atomic, and the app reconciles external daily-note edits through the watcher, but a capture racing an external write to the same file in the read-write window can lose one side. A future hardening could re-read on an mtime change and retry.
- Multiline capture fidelity: `CaptureFormatter` trims each line and re-indents continuations by two spaces, so pasted code loses its original indentation. Acceptable for quick text; revisit if captures need to preserve code blocks verbatim.

## Milestone 3 follow-ups (deferred simplifications)

- Recurrence: not built in Milestone 3 because the acceptance criteria are rollover, completed-task exclusion, duplicate prevention, and clean Markdown. Add conservative recurrence tokens later only after real repeated-task examples justify it.
- Note-relative due resolution: `due:today` and `due:tomorrow` are stored and bucketed as literal tokens, not resolved against the note's own date. A `due:today` from a past note still reads as Due today. Resolving it correctly is natural-language date logic; revisit when rollover re-stamps dates on the rolled-forward reference.
- Open Loops bucket coverage: the read path implements Due today, Overdue, Upcoming, Waiting on others, and No date. The INTERACTION_SPEC buckets "Waiting on me", "Rolled repeatedly", and "Codex tasks" wait on rollover state and Codex, which are later work.
- Tag and mention extraction is conservative: whitespace-delimited tokens that start with `#` or `@`. Trailing punctuation (`@sarah,`) is kept as part of the token. Tighten only if real notes need it.

## Milestone 4 follow-ups (deferred after closeout)

- Source-note backlink: not built in Milestone 4 because task files and context bundles already include source path, line or block, and excerpt. Backlinking should be a separate explicit approval and idempotent if real use proves the source note needs a return link.
- Existing task-file bundle picker: the app can create a bundle after it creates a task file in the composer. It does not yet open an arbitrary existing task file from `specs/tasks/` for bundle creation.
- Strong duplicate detection: repeated approvals create `-2`, `-3`, and later suffixes instead of overwriting. A future source-indexed duplicate warning can be added after the basic flow is used.
- Created-task receipt as one value: done (2026-06-29 hardening pass). `AppState` now holds a single `CreatedCodexTask` value (relative path plus the exact draft) instead of two parallel optionals, so the both-or-neither state is unrepresentable. Button enable-state moved to `CodexTaskDraft.isWritable` / `CodexContextBundle.isWritable` so the views no longer instantiate file writers just to validate.
- CLI test harness survives the dual-`@main` relink: `swift test --filter CommandTests` corrupts the `daymark` binary and every spawned-process test times out, so the only reliable run is `xcrun xctest` against the prebuilt bundle. Options to make the standard `swift test` invocation safe: have `runDaymark` fail fast when the binary is not a working CLI, or restructure so the two executables do not collide on `@main` during the test link.

## Milestone 5 follow-ups

- Automatic Dynamic Blocks refresh: the app now has an explicit preview and approval surface for Today's note. Do not add refresh on launch, note load, typing, autosave, file watch, or a background timer until there is a separate product decision and a stale-edit safety design.
- Arbitrary-note app refresh: the first app surface refreshes Today's note because that is the only editor surface currently implemented. Refreshing any workspace note should wait for a real note-opening flow.
- Broader tag filtering: the first slice supports exact task tag arguments such as `/daymark open-loops #deal/acme`. More expressive filters should wait for real note examples.

## Milestone 6 follow-ups

- EventKit and account setup: parked. The first meeting-prep slice uses explicit local JSON event snapshots and does not request calendar permissions.
- App meeting picker: parked until the CLI/domain preview and approved export path has real usage.
- Attendee matching and richer people resolution: parked. The first slice matches exact event tags only, because fuzzy people matching would add a new entity-resolution layer.
- ICS parsing: parked. JSON snapshots are the stable first input format; do not hand-roll a broad ICS parser without a dedicated slice.
- Richer meeting context: parked. The first slice cites matched notes, open tasks, Codex task specs, context bundles, and explicit question-like lines. It does not summarize or infer claims.

## Hardening pass follow-ups (2026-06-29)

- App rollover preview and approval: the app still auto-applies rollover into Today on launch (`AppState.runRolloverIfSafe`, `apply: true`). This is in tension with the "generated actions are previewed before execution" invariant (`docs/ACCEPTANCE_CRITERIA.md`), but it is also how the app satisfies the Milestone 3 criterion "incomplete tasks from yesterday roll forward". Removing the auto-apply was considered during the hardening pass and reverted, because removing it without a preview/approval surface (out of M5 scope) would regress that M3 behavior in the app. The deliberate fix is to add an in-app rollover preview/approval surface and then move the launch path to preview-only; treat as its own product decision with an ADR. The CLI already models the explicit path (`daymark rollover` previews, `--apply` writes).
- CLI test support extraction: a shared `CLITestSupport.swift` would dedup the binary discovery, temp-root, process-launch, and file helpers copied across the six `*CommandTests`. Deferred this pass: a shared `runDaymark` on an `XCTestCase` extension collides (overload ambiguity) with the per-file private `runDaymark`, so it forces migrating all six files at once. Do it as its own change that migrates every command-test file together.
- CLI command extraction: `Sources/daymark/DaymarkCLI.swift` is a ~1000-line god struct with one shared `CommandError`. Extracting per-command files (starting with the Dynamic Blocks command) is a new structural pattern; land it as its own ADR-recorded change rather than folding it into a behavior-hardening pass, and keep printed strings and exit codes byte-identical.
- Per-command argument-parse helpers: the `--date` / `--apply` parse loops repeat across five command parsers. Extract a small shared arg helper after the per-command-file pattern exists.
- Preview-basis grouping: `AppState.codexTaskPathBasis` and `codexTaskDateBasis` are loose siblings of the active draft preview; group them with the draft so the `?? Date()` fallback disappears. Low value; do it only if it falls out of a nearby change.

## Milestone 7 follow-ups

- Per-card selective apply of dynamic block patches: v1 refresh previews every affected card, but Apply on any card writes the entire patch set atomically through the existing whole-note path. Selective apply needs its own design pass.
- Expose `DynamicBlockPatch` line ranges publicly so cards can match positionally: today `AppState.dynamicBlockCardPreview(forRegionHash:)` matches a card to its pending patch by command hash, so editing a `/daymark` line between preview and apply leaves that card showing a stale idle state instead of picking up the patch.
- Card-body inline emphasis (bold, italic, code spans) is not reproduced inside dynamic block cards, because `NoteTokenScanner` does not emit those token kinds; the live editor applies them through a separate regex pass that card rendering does not share.
- Unify card-body due-date and tag rendering with the editor's exact drawn pills: cards currently render a due date as a clock glyph plus text and a tag in `accentDeep`, close to but not pixel-identical with the editor's drawn controls.
- Word-count surface: cut from the status bar when the bottom bar was removed. Could resurface in the command palette or as a header hover.
- Tag and wikilink clicks currently prefill the command palette rather than navigating to a real note view; that needs a navigation milestone.
- @people entities and an assignee model: still out of scope, per the M7 spec's non-goals.
- Marker concealment (checkboxes, due dates, rollover markers, provenance) as a user preference, rather than always on.

## Documentation stubs (not implemented)

- `DaymarkStore/EventLog` declares the event vocabulary only. There is no events table and no event-recording path. ADR-003 was amended (2026-06-29) to stop claiming SQLite is the event log.
- `DaymarkAgents/AgentRunStore` is an empty placeholder with no callers.
- The schema tables `entities`, `block_entities`, `source_items`, `agent_runs`, and `events` named in older docs are planned, not built. `docs/ARCHITECTURE.md` now distinguishes implemented from planned.
