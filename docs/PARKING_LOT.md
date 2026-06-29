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
