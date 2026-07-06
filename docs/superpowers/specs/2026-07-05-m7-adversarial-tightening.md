# M7 Adversarial Tightening

Date: 2026-07-05
Status: Draft for implementation
Author: Codex

## What this is

This is a cleanup and reliability pass before M7 acceptance. It keeps the Dynamic Note Surface intact and removes the residue left by several fast, high-substance implementation sessions.

The goal is not to make Daymark smaller for its own sake. The goal is to make the shipped shape easier to trust: fewer retired concepts in live code, fewer duplicated grammars, fewer lifecycle races, and a verification gate that fails only for real reasons.

## Locked intent

These are not open during this pass:

- One native `NSTextView` remains the editor.
- TextKit 2 card islands remain the dynamic-block presentation mechanism.
- Markdown remains the readable source of truth.
- SQLite remains a rebuildable projection.
- AI, network, Gmail, Calendar, app bundling, and new product surfaces stay out of scope.
- Dynamic block writes still go through preview and approval.
- Typing must never wait on indexing, SQLite, AI, network, Calendar, Gmail, or Codex.

## Desired end state

After this pass:

- The required test gate is green on normal developer machines.
- Performance checks still exist, but normal functional tests are not hostage to fixed millisecond ceilings.
- The Codex popover cannot lose a presentation request because its invisible host is not yet attached to a window.
- Retired right-margin and panel concepts are gone from live code and current-truth docs.
- Due-date display grammar has one source of truth.
- The incremental render cache has pure regression coverage for the range-shift cases most likely to break card islands.
- Production comments explain invariants, not the review history that discovered them.
- Repo-wide prose policy scans stay clean.

## Non-goals

- Do not redesign cards, glass, typography, or motion.
- Do not replace the render pipeline.
- Do not add new abstractions around SwiftUI surfaces unless a removed layer creates a clear gap.
- Do not move M7 debts into M8 unless they are explicitly accepted in `docs/PARKING_LOT.md`.
- Do not change user-visible behavior except for fixing the Codex popover lifecycle race and removing stale code paths with no callers.

## Work packets

### Packet A: Make the verification gate reliable

Problem: `NoteTokenScannerPerfTests` currently uses fixed wall-clock assertions in the normal `swift test --skip CommandTests` path. On the review machine, the functional suite failed only because these thresholds missed:

- full 5k-line scan: 95.6 ms observed, 40 ms budget
- default prefix walk: 198 ms observed, 20 ms budget
- paragraph hot path: 1.36 ms observed, 1 ms budget
- fence-supplied scan: 1.45 ms observed, 1 ms budget

Implementation:

- Keep the tests as performance characterization coverage.
- Remove fixed millisecond assertions from the default suite, or gate them behind `DAYMARK_ENFORCE_PERF_BUDGETS=1`.
- Keep functional assertions in the default suite: token counts, line counts, and fence-supplied overload correctness.
- Add at least one relative assertion that is robust across machines, for example fence-supplied scanning should remain materially faster than the default prefix-walk path at the document end.
- Document the opt-in perf command beside the required checks if an env-gated path is used.

Acceptance:

- `swift test --skip CommandTests --build-system native` passes by default.
- Running with the opt-in budget flag still prints the same metrics and enforces budgets.
- No performance test silently disappears.

### Packet B: Close the Codex popover lifecycle race

Problem: `CodexPopoverHost.Coordinator.present(from:appState:)` returns when `host.window` is nil. A presentation request can be consumed before the invisible host is attached to the window.

Implementation:

- Replace the plain `NSView()` host with a small `PopoverAnchorView`.
- The view notifies the coordinator from `viewDidMoveToWindow`.
- `sync(host:appState:)` stores the latest host and `AppState`.
- If `isCodexPopoverPresented == true` and the host has no window, keep the request pending.
- When the host enters a window, present if the state is still true and no popover exists.
- Keep dismiss semantics unchanged: user-driven close still calls `dismissCodexTaskDraft()`, programmatic close does not.

Acceptance:

- Triggering the Codex composer immediately after app launch presents once the window is available.
- Repeated SwiftUI updates do not create duplicate popovers.
- Cancel, click-outside, Esc, and successful Create preserve current behavior.

### Packet C: Remove retired right-margin layers

Problem: the M7 surface retired the sidebar and right margin, but live code still carries margin-era helpers and computed state.

Implementation:

- Delete `MarginPanel` and `.marginPanel()` from `Daymark/UI/DesignSystem/Components.swift`.
- Remove unused computed properties from `AppState`:
  - `createdCodexTaskRelativePath`
  - `isDynamicBlockPreviewStale`
  - `showsDynamicBlockRefreshPanel`
  - `showsContextBundlePanel`
- Update current-truth docs that still describe right-margin panels or `.marginPanel()` as live architecture.
- Do not remove underlying state that is still used by the Codex receipt, context bundle creation, or dynamic block apply path.

Acceptance:

- `rg "marginPanel|MarginPanel|showsDynamicBlockRefreshPanel|showsContextBundlePanel|createdCodexTaskRelativePath|isDynamicBlockPreviewStale" Daymark Sources Tests` returns no live-code hits.
- Docs no longer state that the right margin or `.marginPanel()` is current architecture.
- Codex task creation, context bundle approval, dynamic block refresh, and receipts still build and test.

### Packet D: Centralize due-date display grammar

Problem: `OpenLoopsView` mirrors private due-date display logic from `NoteTokenScanner`. The UI and token scanner can drift.

Implementation:

- Add a Core-owned formatter, preferably `TaskItem.Due.displayText(calendar:)` or a small `DueDisplay` helper.
- Preserve exact output:
  - `Today`
  - `Tomorrow`
  - `MMM d` for ISO dates, using Gregorian calendar and `en_US_POSIX`
  - raw ISO string fallback when parsing fails
- Use the helper from both `NoteTokenScanner` and `OpenLoopsView`.
- Keep scanner caching only if it still pays for itself after the helper is extracted.

Acceptance:

- Existing due-token tests continue to pass.
- Add focused tests for `.today`, `.tomorrow`, valid ISO date, and invalid ISO fallback.
- `rg "Mirrors NoteTokenScanner|private static let dueFormatter|private static func dueDisplay" Daymark Sources Tests` shows no duplicated UI formatter.

### Packet E: Put regression tests under the render-cache reducer

Problem: `LiveRenderController.mergeIntoCache` now owns line shifts, inline token shifts, region shifts, fence-state shifts, and reveal-fade shifts. The behavior is too important to protect only through manual app testing.

Implementation:

- Extract the pure range-shift logic into a small testable type. Good names:
  - `LiveRenderCacheReducer`
  - `NoteTokenCacheReducer`
  - `RenderTokenCache`
- Keep AppKit and SwiftUI out of the extracted type.
- The reducer should accept old cache state, edited range, replacement length, and rescanned tokens for the affected lines.
- `LiveRenderController` remains the owner of applying attributes and scheduling fades.
- Do not expose this as public product API unless tests require it.

Required tests:

- Insert a newline above an in-flight reveal fade; fade range shifts and overlay does not double-render.
- Delete a line above a generated region; region start, end, and command line shift together.
- Edit inside a generated region; only the touched region is invalidated or replaced according to existing behavior.
- Paste multiple lines into the middle of the note; downstream line starts and fence states remain correct.
- Edit a fence marker above a task-looking line; task tokenization follows the new fence state.

Acceptance:

- The reducer tests fail against at least one intentionally broken shift variant during local development.
- No interactive path forces full-document layout as a correctness fallback.
- No code touches `NSTextView.layoutManager`.

### Packet F: Clean production comments and prose policy

Problem: some production comments carry review labels like `Bug 2`, `Finding 5`, and one-off measurement history. Those notes were useful while debugging; they are noise once the invariant is known.

Implementation:

- Keep comments that protect future maintainers from subtle TextKit, window-lifecycle, or range-shift mistakes.
- Rewrite review-history comments into invariant comments.
- Remove labels like `Bug N`, `Finding N`, and old benchmark anecdotes from production code.
- Preserve intentionally useful test comments when they explain why a case exists.
- Replace literal em dash test strings with escaped Unicode, for example `"\u{2014}"`, and use policy-clean assertion messages.

Acceptance:

- `rg "Bug [0-9]|Finding [0-9]|measured at|review pass" Daymark Sources Tests` has no production-code hits. Test names or comments may remain only when they describe a durable regression category.
- The repo prose-policy scan is clean, including no literal em dash characters. Intentional Unicode checks should use escaped literals such as `"\u{2014}"`.

## Order of operations

1. Packet A first. The gate should be trustworthy before the cleanup begins.
2. Packet B second. It is a real lifecycle bug with user-visible failure potential.
3. Packet C and Packet D next. These are clean reductions with low blast radius.
4. Packet E after the smaller cuts. It is the most valuable reliability work, but it touches the most subtle code.
5. Packet F last, so comment cleanup reflects the final code shape.

## Required checks

Use the M7 toolchain rules:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --skip CommandTests --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product Daymark --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product daymark --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-tests --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product daymark --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun xctest .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest
.build/arm64-apple-macosx/debug/daymark doctor
git status --short
```

Also run the temp-workspace Dynamic Blocks check from `docs/PROGRESS.md` before closing the pass.

## Definition of done

This pass is done when the code has fewer live concepts than it started with, the same user-facing M7 behavior, and a gate that a future maintainer can run without knowing the story of the last several sessions.

The intended final review sentence is simple: M7 still feels like the same product, but the implementation has fewer retired concepts, fewer duplicated rules, and better tripwires around the hard parts.
