# Milestone 7: Dynamic Note Surface

Date: 2026-07-05
Status: Draft for Samay's review
Author: Fable 5 (spec, decomposition, gates); implementation routed to lower tiers per `~/.claude/FABLE-ORCHESTRATION.md`

## What this is

Daymark's UI becomes a single-pane, note-centric surface in the style of Char (char.com) and Antinote, built on Daymark's warm-paper identity and its existing deterministic engines. Today's note is the app. Checkboxes become real controls, tags and links become pills, dynamic block regions render as inline cards, and the Codex composer becomes a popover anchored to the selection. No AI, no network, no new engines. The presentation and interaction layer catches up to what `reference/mockups/` always showed.

Char patterns adopted: date-tile day header, brief strip, entity-rich task lines, inline generated-content cards with approval, artifact receipts. Char patterns explicitly not adopted: dark theme, marker concealment for headings, chat input, @people entities, AI summaries.

## Locked decisions

These were decided with Samay on 2026-07-05 and are not open for re-litigation by builders:

- Warm light theme. Char's structure, Daymark's palette. No dark mode work.
- Deterministic-only. Every dynamic behavior is backed by an existing local engine (rollover, open loops, dynamic blocks, Codex handoff). Model calls stay parked.
- Single-pane, note-centric. Sidebar and right-margin panels retire. Overlays and inline cards replace them.
- Editor approach: live-styled text plus card islands. One `NSTextView`, buffer stays literal Markdown, TextKit 2 presentation for generated regions. ADR-001 stands.
- Markdown files remain the source of truth; SQLite remains a rebuildable projection; typing never blocks; every write outside the buffer keeps its preview/approve gate.

## Non-goals

Out of scope for this milestone, enforced at review gates:

- AI, Gmail, EventKit, network calls, embeddings, Codex execution.
- @people mentions, avatars, assignee model.
- Heading/emphasis marker concealment (markers stay visible, styled quiet).
- Block-composite editing, note navigation to arbitrary files, multi-note tabs.
- Per-card selective apply of dynamic block patches (v1 previews per card, applies the whole-note patch set atomically through the existing hardened path).
- Writing artifact chips or backlinks into source notes (stays in `docs/PARKING_LOT.md`).
- System-global hotkey, app bundling, iOS.

## Product specification

### Window and shell

- `RootView` becomes: one centered editor column over the canvas, with overlay layers (capture slip, command palette, Open Loops overlay, Codex popover, receipt card). The `HStack` of sidebar/content/margin is deleted.
- Sidebar (`SidebarView.swift`) is deleted. Its two functional destinations survive: Today is the root view; Open Loops becomes an overlay (⌘L). Settings stays in the `Settings` scene. The non-functional rows (Notes, Scratchpad, Calendar, Archive, Tags) are removed with their `SampleData` backing; they return only when a real milestone builds them.
- Context margin (`ContextMarginView.swift`, `DynamicBlockRefreshView.swift` as a panel, margin-card Codex composer) is deleted. Its jobs move inline (dynamic block cards) and to the popover/receipt (Codex).
- Window: default 860x720, minimum 620x520. Editor column max width stays 720 with 48pt top padding. Hidden titlebar and light-mode enforcement stay as they are.
- Launch frame: the window NEVER opens maximized or zoomed. On launch, if the restored frame covers 90 percent or more of the screen's visible frame (width or height), reset to the default 860x720, centered on the active screen. A user resize during a session is respected and restored next launch only when it stays under that threshold. The zoom button keeps working normally after launch.
- Materials and depth: the writing canvas stays opaque warm paper (no blur under body text, ever). Depth lives in the chrome. The day header is a material band (`NSVisualEffectView`, within-window blending, warm tint overlay at roughly 0.85 canvas opacity): note content visibly blurs beneath it as it scrolls under, and a hairline appears on its bottom edge only once content has scrolled. Every floating surface (command palette, capture slip, Open Loops overlay, receipt card, Codex popover) sits on native material (`.regularMaterial` or the AppKit equivalent) with hairline borders, not flat opaque fills; scrims dim the canvas as today. The titlebar region stays transparent so the window reads as one continuous sheet. When the system Reduce Transparency accessibility setting is on, every material degrades to its opaque token fill (header to canvas, panels to surface).
- The custom top bar in `TodayView` is replaced by the day header below. Back/forward chevrons (currently dead) are removed. The bottom status bar is removed; save state moves into the brief strip. Word count is cut (parking lot: surface it in the palette).
- The conflict banner stays, restyled as a card: `surface` background, `panelRadius`, hairline border, same actions.

### Day header

Top of the note column, above the editor, part of the app chrome (not note text):

- Date tile: 48x48, `surfaceWarm` fill, hairline border, radius 10. Day-of-month numeral, 26pt semibold, `textPrimary`, centered.
- To the tile's right: month name 16pt semibold `textPrimary`, weekday 13pt `textSecondary`, stacked, 2pt gap.
- Brief strip, one line under the tile row, 13pt `textSecondary`, middot separators. Segments in order, each omitted when zero/empty: "N rolled over", "N open loops", save state ("Saved" steady; "Saving" during debounce flush). Rolled-over count comes from the launch rollover result; open loops count is the live count `AppState` already maintains.
- Clicking the brief strip opens the Open Loops overlay. Hover: `textPrimary` at 80ms ease-out. No other affordance.
- Header right edge: three quiet 22pt icon buttons (capture slip, command palette, open loops), same hover treatment as today's `ToolbarIcon`.

### Live note body

The buffer is always the literal Markdown on disk. Styling is attribute-only plus drawn controls. Line grammar comes from `NoteTokenScanner` (below), which reuses the semantics of `TaskParser`, `DynamicBlockParser`, and `MarkdownFenceScanner`; fenced code content never tokenizes.

Token catalog and treatment:

| Token | Source syntax | Rendering | Interaction |
|---|---|---|---|
| Heading | `#`..`###` | Marker chars tinted `accent`, title weighted per level (H1 24, H2 19, H3 17 semibold). Unchanged from today. | None |
| Task, open | `- [ ] text` | Leading `- ` dimmed `textTertiary`. The 3-char `[ ]` is concealed and a 16x16 drawn checkbox (radius 4, `checkboxBorder` stroke) renders in its rect. Text is body 16. | Click checkbox: toggle. Hover: stroke turns `accent`. |
| Task, done | `- [x] text` | Same geometry; checkbox fills `accent` with white check; text struck through in `textSecondary` (as today). | Click: untoggle |
| Caret in marker | caret or selection intersects the `[ ]`/`[x]` range | Literal characters reveal (concealment drops) so editing is honest | Normal text editing |
| Tag | `#launch` | Pill: `accentSoft` fill, `accentDeep` text, radius 4, 3pt horizontal pad. Not inside headings' marker runs; not in fences. | Click: open command palette prefilled with the tag |
| Wikilink | `[[name]]` | `accent` text, brackets dimmed `textTertiary`, underline on hover only | Click: open palette prefilled with name |
| URL | autodetected http(s) | `accent`, underline | Click: open in default browser (`NSTextView` link attribute) |
| Due date | `TaskParser`'s existing due-token grammar, verbatim | Pill: `surfaceWarm` fill, `textSecondary` text, SF Symbol `clock` 11pt leading. Date humanized: "Today", "Tomorrow", else "Jul 8" | None in v1 |
| Command line | `/daymark <known command>` | SF Mono 13 `accent`. No background. | None (its card carries the actions) |
| Quote, bullet, code span, bold, italic | as today | Unchanged from `MarkdownHighlighter` | None |

Checkbox toggle is a normal text edit: replace `[ ]` with `[x]` or the reverse via the undo-coalesced text path, which fires `textDidChange`, the 800ms debounced autosave, and the indexer, exactly like typing. `TaskCheckboxToggler` in DaymarkCore owns the string math and is unit-tested; the view layer never computes ranges itself.

Keyboard parity (required by `reference/cold-start-craft/extension-interaction-contract.md`): ⌘Return toggles the checkbox on the caret line when that line is a task; otherwise it is a no-op beep-free pass-through.

### Dynamic block card islands

This is the core deliverable of the milestone, not an enhancement. The dynamic-document feel (generated content as first-class inline cards) is what makes the idea useful; a degraded rendering of well-formed regions does not ship.

A generated region (`<!-- daymark:block-begin <hash> -->` ... `<!-- daymark:block-end <hash> -->`) renders as one embedded card in place of its literal text. The literal text never leaves the buffer; copy/paste over a region yields raw Markdown.

Card chrome: `surface` fill, hairline border, `panelRadius` (12), 14pt padding, full column width. Header row: block title derived from the command (`/daymark open-loops` renders "OPEN LOOPS", `source-list` "SOURCES", `codex-context` "CODEX CONTEXT", `weekly-review` "WEEKLY REVIEW"), 12pt semibold `textSecondary`, tracking +0.5; right side: "generated <relative time>" from `.daymark/dynamic-blocks.json` when available (omit when absent), a refresh icon button, and a view-source toggle (curly-brace icon). Body: the region's inner Markdown rendered read-only with the same token styling as the editor.

States:

- Idle: as above.
- Preview pending (after refresh): a one-line change summary per the existing patch model ("will replace 6 lines"), body shows the incoming content, footer gains Apply and Cancel buttons (`PrimaryButtonStyle` / `QuietButtonStyle`).
- Stale: if the buffer changes after preview, Apply disables and the summary line reads "Note changed; preview again" (existing buffer-hash guard, surfaced per card).
- Source revealed: literal region text shows; the card chrome collapses to a thin header strip pinned above the region. Toggling back re-collapses. Moving the caret into the region with arrow keys or a click on revealed text also reveals; moving it out re-collapses.

Refresh semantics, v1: refresh (per-card button, ⇧⌘R, or the palette action) runs the existing whole-note `DynamicBlockRefreshService.preview`; every affected card shows its pending state; Apply on any card (or the palette action) applies the entire patch set atomically through `applyDynamicBlocksRefresh`, exactly the hardened M5 path. Cancel clears all pending previews. Selective per-card apply is a parking-lot item.

Malformed regions (unpaired begin, hash mismatch, nested markers): no card. The literal text renders with plain styling. Content is never hidden unless the region parses as a complete, well-formed pair. This matches the M5 hardening rule that a stray begin marker must not hide following content.

Card body checkboxes are read-only (generated checklists are display artifacts; M5 already guarantees they do not feed back into task scans). Toggling requires revealing source, which makes the edit explicit.

### Codex composer and receipts

- ⇧⌘C (or the palette action) with a selection or current block opens an `NSPopover` anchored at `firstRect(forCharacterRange:)` of the selection, hosting the existing `EditableCodexTaskDraftView` field set (Title, Goal, Constraints, Acceptance, read-only source and Markdown) restyled to the new tokens. Create/Cancel as today; same `AppState` logic, same collision-safe write under `specs/tasks/`.
- On create, the popover closes and a receipt card slides up at the column's bottom-right: task title, relative path, and actions "Reveal in Finder", "Copy path", "Create context bundle", "Done". Receipt persists until dismissed; it is app chrome, never note content.
- "Create context bundle" expands the receipt into the existing bundle preview (derived from the exact approved draft, as today); Approve writes under `artifacts/context-bundles/` and the receipt updates with the bundle path. All existing invalidation rules stand (editing the draft or starting a new preview clears the offer).
- `SuggestionCardView` (static prompt, no-op dismiss) is deleted; the palette and ⇧⌘C are the entry points.

### Restyled existing surfaces

- Capture slip: behavior identical (⌥Space, Return/⇧Return/⌘Return/⇧⌘T/Esc). Restyle: `surface` fill, `panelRadius`, hairline, new type scale. Copy stays "Capture to Daymark."
- Command palette: behavior identical plus action-list changes (add "Open Loops", remove "Toggle Context Margin"; "Refresh Dynamic Blocks" stays, gated as today). Restyle to tokens; prefill support (invoked with an initial query string) for tag/wikilink clicks.
- Open Loops: same data and grouping, presented as a centered overlay (560 wide, 70% max height, scrim, Esc closes, ⌘L toggles). Row restyle to the new checkbox and pill treatments. Row actions unchanged.
- Settings scene: untouched.

### Keyboard map after this milestone

| Keys | Action |
|---|---|
| ⌘1 | Today (unchanged) |
| ⌘K | Command palette |
| ⌥Space | Capture slip (app focused) |
| ⇧⌘C | Codex popover |
| ⇧⌘R | Refresh dynamic blocks (preview all) |
| ⌘L | Open Loops overlay (new) |
| ⌘Return | Toggle checkbox on caret line (new) |
| Esc | Close topmost overlay/popover |

⌥⌘\ (margin toggle) is removed with the margin.

## Visual spec: token additions

Add to `DesignTokens` (existing values unchanged; hex exact):

| Token | Value | Use |
|---|---|---|
| `accentDeep` | `#4F634F` | Tag pill text (contrast >= 4.5:1 on `accentSoft`) |
| `checkboxBorder` | `#C9C5BE` | Empty checkbox stroke |
| `pillDueFill` | `surfaceWarm` alias | Due pill fill |
| `cardIslandFill` | `surface` alias | Card island fill |
| `dateTileFill` | `surfaceWarm` alias | Date tile fill |

Add to `DesignMetrics`: `checkboxSize = 16`, `checkboxRadius = 4`, `pillRadius = 4`, `dateTileSize = 48`, `dateTileRadius = 10`, `windowWidth = 860`, `windowHeight = 720`, `minWindowWidth = 620`, `minWindowHeight = 520` (replacing current window numbers), `sidebarWidth` and `contextMarginWidth` deleted.

Add to `DesignType`: `dateTileNumeral` 26 semibold, `cardHeader` 12 semibold, `pill` 13.

Motion (all within existing budgets; every new animation checks Reduce Motion and degrades to a plain state swap):

| Interaction | Spec |
|---|---|
| Checkbox complete | Existing `DesignMotion.checkbox` spring, check path draw, <= 140ms total |
| Card preview state in/out | 160ms ease-out opacity+2pt rise |
| Card source reveal/collapse | 180ms height + opacity, no bounce |
| Receipt card in | 160ms ease-out rise; out 120ms |
| Open Loops overlay | 160ms in / 120ms out, scrim fade |
| Popover | System `NSPopover` behavior |

Fonts stay Apple system (SF Pro / SF Mono) per `docs/DESIGN_SYSTEM.md`. Radii cap at 12. No shadows beyond the existing panel treatment; hairlines preferred.

## Architecture

### New in DaymarkCore (pure, dependency-free, fully tested)

New directory `Sources/DaymarkCore/NoteTokens/`:

```swift
public struct NoteTokens: Sendable, Equatable {
    public struct GeneratedRegion: Sendable, Equatable {
        public let hash: String
        public let range: NSRange          // full range incl. markers, UTF-16
        public let innerRange: NSRange     // content between markers
        public let commandLineRange: NSRange?  // the /daymark line above, when adjacent
    }
    public enum LineKind: Sendable, Equatable {
        case heading(level: Int, markerRange: NSRange)
        case task(done: Bool, markerRange: NSRange, boxRange: NSRange, textRange: NSRange)
        case bullet(markerRange: NSRange)
        case quote
        case commandLine(command: String)
        case fence
        case body
        case blank
    }
    public struct Line: Sendable, Equatable {
        public let range: NSRange
        public let kind: LineKind
    }
    public enum InlineKind: Sendable, Equatable {
        case tag, wikilink, url, dueDate(display: String), codeSpan, bold, italic
    }
    public struct InlineToken: Sendable, Equatable {
        public let range: NSRange
        public let kind: InlineKind
    }
    public let lines: [Line]
    public let inlineTokens: [InlineToken]
    public let regions: [GeneratedRegion]
}

public enum NoteTokenScanner {
    public static func scan(_ text: String) -> NoteTokens
    public static func scanLines(_ text: String, in lineRange: NSRange) -> NoteTokens  // incremental
}
```

Rules: all ranges are UTF-16 (`NSRange`-compatible, emoji-safe). Fence detection delegates to `MarkdownFenceScanner`; nothing inside a fence tokenizes except the fence lines themselves. Task grammar matches `TaskParser` exactly, including its due-token grammar (the builder reads `TaskParser` as the grammar reference; divergence is a bug). Region detection matches `DynamicBlockParser` marker semantics including the complete-pair and hash-aware rules from the M5 hardening. CRLF input scans correctly and ranges account for the `\r`.

```swift
public enum TaskCheckboxToggler {
    public struct Edit: Sendable, Equatable {
        public let range: NSRange          // the 1-char box interior, e.g. " " or "x"
        public let replacement: String
    }
    public static func toggleEdit(in text: String, atLineContaining location: Int) -> Edit?
}
```

Returns nil when the location's line is not a task line or lies inside a generated region or fence. Preserves indentation, metadata, and CRLF.

### App shell changes

- `LiveRenderController` (new, `Daymark/Editor/`) replaces `MarkdownHighlighter`. On `textDidChange` it re-scans only the edited paragraph range synchronously via `scanLines` and applies attributes there; a debounced (150ms) full `scan` reconciles cross-line constructs (fences opened/closed, region markers). Attribute application is display-only, as today.
- Checkbox rendering: the `[ ]`/`[x]` glyph run is concealed (clear foreground) and a checkbox control draws in its bounding rect; the leading `- ` stays visible dimmed. When the caret or selection intersects the box range, concealment drops. The Opus builder may implement the control as per-line overlay views or as custom `NSTextLayoutFragment` drawing; both are acceptable if every acceptance criterion passes. This is the only granted implementation latitude in this spec.
- Click routing: `NSTextView` subclass hit-tests mouse-down against `NoteTokens` ranges (checkbox first, then pill/link ranges) before falling through to caret placement.
- Card islands: TextKit 2 (`NSTextLayoutManager` delegate) supplies a custom layout fragment for each well-formed region, collapsing its visual height to the card and positioning an `NSHostingView`-backed SwiftUI card in the fragment frame. The text view runs TextKit 2 only; nothing may touch `layoutManager` (which would trigger the TextKit 1 fallback and must fail review). The card outcome is pinned: collapsed source, real card chrome, interactive controls, caret reveal. Only the mechanism is open, between the fragment approach and precisely positioned hosted overlays with region height suppression, and the Phase 1 feasibility spike decides which one Phase 3 builds. Rendering well-formed regions as visible tinted text is not a shipping option; it remains solely the degradation for malformed markers.
- Selection and copy: selections crossing a collapsed region select the literal text; copy always yields buffer text. Caret arrow-key entry into a region reveals it (see card states).
- `AppState`: margin state (`isContextMarginVisible`, margin panel plumbing) is deleted. Added: `isOpenLoopsOverlayPresented`, Codex popover presentation state, receipt state, rollover-count exposure for the brief strip. Engines (`DynamicBlockRefreshService`, rollover, Codex writers, watcher reconciliation, conflict flow) are untouched.
- Module boundaries hold: scanning/toggling in Core; AppKit/SwiftUI/TextKit in the shell; Store and Indexer untouched this milestone (except no changes needed); CLI untouched.

### Performance budgets (enforced at the Phase 2 gate)

- Keystroke path: synchronous paragraph re-scan plus attribute application under 1ms for a typical daily note; no allocation storms (reuse token buffers where practical).
- Debounced full scan under 15ms on a 5,000-line note.
- No I/O, no SQLite, no scanning of other files on the keystroke path (unchanged invariant).
- Measurement: signpost or `CFAbsoluteTimeGetCurrent` timing logged in debug builds; the gate check types into a generated 5k-line note and reads the timings.

## Edge cases

- Malformed region markers: literal text, plain styling, no card, nothing hidden.
- Region at note start or end, back-to-back regions, region whose command line was deleted: card renders from markers alone (header title falls back to the block name recorded in the region content header line, else "GENERATED").
- Checkbox toggle inside a generated region: `TaskCheckboxToggler` returns nil; the click reveals source instead.
- Undo: checkbox toggles and applied refreshes are ordinary undoable text edits.
- External edit during preview: existing watcher reconciliation plus stale-preview guard; the card shows the stale state.
- Conflict banner and slip/palette overlays: only one modal surface at a time; Esc closes the topmost; opening the palette closes the slip and vice versa (today's behavior, made explicit).
- Empty note / template note: header renders; brief strip shows only what exists; editor is immediately typable (unchanged launch contract).
- Reduce Motion on: every animation in the motion table becomes an instant state swap; the check draw becomes a fade.

## Testing and acceptance

New tests (XCTest, matching house style):

- `NoteTokenScannerTests` (Core): headings, tasks (open/done/nested/indented), tags, wikilinks, URLs, due tokens, command lines, fences excluding all tokens, well-formed regions, unpaired begin, hash mismatch, adjacent regions, CRLF, emoji offsets, empty string. Minimum 20 cases.
- `TaskCheckboxTogglerTests` (Core): open to done and back, indentation preserved, metadata preserved, non-task lines nil, inside-region nil, inside-fence nil, CRLF, emoji-heavy text.
- Existing suites must pass untouched: `swift test --skip CommandTests` (202 tests plus the new ones), CLI slice via the prebuilt-xctest flow in `docs/PROGRESS.md` Required Checks, `swift build --product daymark`, `swift build --product Daymark`.
- The temp-workspace Dynamic Blocks check from Required Checks passes unchanged (the service and Markdown semantics did not move).

Acceptance criteria per surface (the Phase 4 taste gate walks this list against the running app):

- Launch to typable Today under the existing launch contract; header shows correct date, counts, and save state.
- Clicking a checkbox toggles it with the spring; the file on disk contains the flipped `[x]` within the autosave window; undo restores it.
- ⌘Return parity works; caret in the box range reveals literal `[ ]`.
- Tags, wikilinks, URLs, due dates render as specified; tag click prefills the palette.
- A note with all four block commands renders four cards; refresh previews on-card; apply writes markers idempotently; repeat apply produces no duplicates; stale preview disables apply; view-source reveals literal text; malformed markers degrade to literal text.
- Codex flow end to end: select, ⇧⌘C, edit fields, create, receipt appears, bundle creation from the receipt works, files land collision-safe, source note untouched.
- Open Loops overlay opens from ⌘L, brief strip, and palette; Esc closes.
- Reduce Motion honored across every new animation; Reduce Transparency degrades every material to its opaque token fill.
- Window opening behavior: zoom the window, quit, relaunch; the window opens compact (860x720 centered), never maximized. A modest user size (for example 900x800) restores normally.
- Header material: scroll a long note; content blurs beneath the header band and the bottom hairline fades in only after scroll begins.
- No regression: capture slip flows, conflict banner, watcher reconciliation, palette search.

## Execution plan

Doctrine: `~/.claude/FABLE-ORCHESTRATION.md`. Fable writes no implementation code. Every packet carries an explicit model tier and effort; builders return structured reports (files touched, tests run and results, deviations, open questions), never file dumps. A packet a builder cannot complete comes back as a question, not a guess. Ledger at `docs/orchestration/LEDGER.md`, updated at each phase boundary; success bar: Fable at or below 20 percent of session output tokens.

Phases are serial; packets within a phase parallelize only when file ownership is disjoint.

### Phase 0 (Fable, paperwork only)

ADR-012 (this direction: single pane, live-styled editor, card islands, popover composer, margin retirement, roadmap renumber). `docs/ROADMAP.md`: insert Milestone 7 Dynamic Note Surface; Gmail becomes M8, iOS capture M9. Create the ledger file. Commit spec and paperwork.

### Phase 1: foundations

| Packet | Model, effort | Owns | Contract |
|---|---|---|---|
| P1-scanner | Sonnet, medium | `Sources/DaymarkCore/NoteTokens/*` (new), `Tests/DaymarkCoreTests/NoteTokenScannerTests.swift`, `TaskCheckboxTogglerTests.swift` (new) | APIs exactly as specified; grammar parity with `TaskParser`/`DynamicBlockParser`/`MarkdownFenceScanner` (read-only references) |
| P1-tokens | Haiku, low | `Daymark/UI/DesignSystem/DesignTokens.swift`, `Components.swift` | Token/metric/type additions exactly as the visual spec tables; pill and checkbox style helpers |
| P1-shell | Sonnet, medium | `Daymark/UI/RootView.swift`, `TodayView.swift`, `MenuCommands.swift`, `AppState.swift`, `SampleData.swift`, `CommandPaletteView.swift` (actions only), delete `SidebarView.swift` | Runs after P1-tokens merges. Shell per the product spec; no editor changes |
| P1-spike | Opus, high | A standalone throwaway SwiftPM prototype outside the repo (session scratchpad); nothing in the repo tree | Prove the card mechanism before anything depends on it: an editable TextKit 2 `NSTextView` where a marker-delimited region collapses to an interactive hosted SwiftUI card (buttons work), caret entry reveals literal text, selection/copy yields the literal text, typing latency stays flat. Try the custom-fragment approach first, the positioned-overlay approach second. Returns a structured report: which mechanism passed, code sketch of the working core, sharp edges found |

Order: all four packets run in parallel except P1-shell, which starts after P1-tokens merges. Gate: mechanical (full library suite, both product builds, app launches and types) plus the spike verdict. The spike verdict selects the mechanism P3-cards implements; if neither mechanism passes the spike, the milestone halts for a redesign conversation with Samay rather than shipping a degraded card.

### Phase 2: live editor

| Packet | Model, effort | Owns | Contract |
|---|---|---|---|
| P2-editor | Opus, high | `Daymark/Editor/*` (replace `MarkdownHighlighter` with `LiveRenderController`, extend the representable and text view subclass, delete dead `CheckboxOverlay.swift`) | Token treatments, checkbox conceal/click/reveal, ⌘Return, pills, link routing, incremental scan, perf budgets. Latitude only where the spec grants it |

Gate: mechanical (suite, builds) plus adversarial (Opus reviewer, high effort, prompted to refute: buffer mutation from the render path, TextKit 1 fallback trips, range drift on emoji/CRLF, latency claims) with findings verified before acting, plus the typed 5k-line latency check.

### Phase 3: cards, popover, receipts

Serial pipeline (shared `AppState` and editor surfaces):

| Packet | Model, effort | Owns | Contract |
|---|---|---|---|
| P3-chrome | Sonnet, medium | `Daymark/DaymarkApp.swift`, `Daymark/UI/RootView.swift`, `Daymark/UI/Today/TodayView.swift` (chrome only) | The launch-frame guard (never opens maximized) and the materials spec: header material band with scroll blur and scroll-edge hairline, transparent titlebar region, Reduce Transparency fallbacks. Runs first in the pipeline |
| P3-cards | Opus, high | `Daymark/Editor/CardIslands/*` (new) | Implements the mechanism the P1 spike proved: region collapse, hosted interactive card container, reveal-on-caret, selection/copy rules. No degraded rendering path for well-formed regions |
| P3-cardui | Sonnet, medium | `Daymark/UI/Cards/DynamicBlockCardView.swift` (new), delete `DynamicBlockRefreshView.swift`, `AppState.swift` (refresh + overlay + receipt state) | Card states table; v1 whole-note refresh semantics |
| P3-codex | Sonnet, medium | `Daymark/UI/Codex/*` (new popover + receipt), delete `ContextMarginView.swift`, `CodexTaskComposerView.swift`, `SuggestionCardView.swift` | Popover anchoring, receipt flow, bundle offer rules unchanged |

Gate: mechanical (suite, builds, temp-workspace Dynamic Blocks check) plus adversarial review on P3-cards, plus Fable taste pass on screenshots.

### Phase 4: polish and docs

| Packet | Model, effort | Owns | Contract |
|---|---|---|---|
| P4-restyle | Sonnet, low | `SlipPanelView.swift`, `CommandPaletteView.swift` (visuals), `OpenLoopsView.swift` (overlay conversion + rows) | Restyle only; behavior frozen. Floating surfaces adopt the materials spec (native material fills, hairline borders, opaque Reduce Transparency fallback) |
| P4-polish | Opus, medium | Any visual code under `Daymark/UI/` and `Daymark/Editor/` (behavior frozen), serial after the other P4 packets | Implements Fable's taste-gate findings from screenshots; iterates until the taste gate passes. The bar is Char-level finish on Daymark's warm identity |
| P4-cleanup | Haiku, low | Dead-code sweep of removed references, Reduce Motion audit against the motion table, slopcheck over changed files | Report findings; delete only what the spec removed |
| P4-docs | Sonnet, low | `docs/DESIGN_SYSTEM.md`, `docs/INTERACTION_SPEC.md`, `README.md`, `docs/PROGRESS.md` (dated entry), `docs/PARKING_LOT.md` | Docs reflect the shipped surface; parking lot gains the items listed below |

Gate: full Required Checks from `docs/PROGRESS.md`, acceptance-criteria walk on the running app, Fable taste gate on screenshots, ledger final report.

### Escalation rule for builders

If the spec is silent or two readings are possible, stop and return the question in the structured report. Do not invent design. The two named latitudes (checkbox drawing strategy; card mechanism, chosen at the Phase 1 gate from spike-proven options) are the only open implementation choices.

## Parking lot additions (Phase 4 records these)

- Per-card selective apply of dynamic block patches.
- Word count surface (palette or header hover).
- Artifact backlink chips written into source notes (opt-in, approval-gated).
- Tag/wikilink click navigating to a real note view (needs a navigation milestone).
- @people entities and assignee model.
- Marker concealment mode as a preference.

## Risks

- The card mechanism is the highest-risk item and also the core of the product; it gets de-risked first (P1 spike proves it in isolation before anything depends on it), then built by Opus in P3-cards behind its own adversarial gate. There is no degraded shipping path; if both mechanisms fail the spike, the milestone pauses for a redesign conversation.
- Checkbox concealment can drift on variable-width fonts; acceptance pins reveal-on-caret and emoji-safe ranges, and the toggle math lives in tested Core code.
- Deleting the margin removes the only current visible home of the Codex bundle offer; the receipt flow replaces it and the acceptance walk covers the full chain.
- Latency regressions from full-note scans; the incremental contract plus the 5k-line gate check hold the line.
