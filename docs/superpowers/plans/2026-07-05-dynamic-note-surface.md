# Milestone 7: Dynamic Note Surface Implementation Plan

> **For agentic workers:** This plan executes under `~/.claude/FABLE-ORCHESTRATION.md` via packet subagents with explicit model tiers, not via a single inline session. The orchestrator (Fable) dispatches packets, runs gates, and commits; builders never run `git commit`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Daymark's presentation layer as a single-pane, Char-style dynamic note (live checkboxes, entity pills, inline dynamic-block cards, popover Codex composer) on the existing deterministic engines, per `docs/superpowers/specs/2026-07-05-dynamic-note-surface-design.md`.

**Architecture:** Pure tokenization (`NoteTokenScanner`, `TaskCheckboxToggler`) lands in DaymarkCore with full tests. The app shell collapses to one editor column plus overlays. The editor stays one TextKit 2 `NSTextView` with attribute-only live styling; well-formed generated regions render as embedded interactive cards using the mechanism a Phase 1 spike proves.

**Tech Stack:** Swift 6 / SwiftPM, XCTest, AppKit `NSTextView` + TextKit 2, SwiftUI shell, no new dependencies.

## Global Constraints

Every packet inherits these. Copy verbatim into packet prompts.

- The spec is law: `docs/superpowers/specs/2026-07-05-dynamic-note-surface-design.md`. If the spec is silent or ambiguous, stop and return the question in your report. Do not invent design.
- Markdown buffer stays literal disk text; styling is attribute/presentation only. Never mutate `NSTextStorage` characters from a render path.
- Typing never blocks: no I/O, SQLite, or full-note scans on the keystroke path. Budgets: paragraph re-scan under 1ms typical; debounced full scan under 15ms on a 5,000-line note.
- Module direction: Core has no dependencies; Store/Indexer/Agents/CLI untouched this milestone; AppKit/SwiftUI only in `Daymark/`.
- Tests are XCTest, matching existing style (`Tests/DaymarkCoreTests/TaskParserTests.swift` is the reference). TDD: write failing tests first, show them fail, implement, show green.
- Design tokens: warm light only; radii cap 12; motion within `DesignMotion` budgets (nothing over 220ms); Apple system fonts only; Reduce Motion degrades every new animation to a state swap.
- Library suite: `swift test --skip CommandTests`. If relink fails with `Undefined symbols: _DaymarkCLI_main`, run `swift package clean` first. CLI tests are NOT run per-packet (no CLI changes in this milestone); the phase gate runs them via the prebuilt-xctest flow in `docs/PROGRESS.md` Required Checks.
- Builders do not commit, push, or touch files outside their packet's ownership list. Return a structured report: files touched, tests added/run with results, deviations, open questions, and (for spikes) verdicts.
- No em dashes anywhere, including comments and docs. No decorative comments; match the surrounding code's comment density (near zero).

## Interface Registry (cross-packet contract)

Names below are binding. A later packet consumes exactly these.

```swift
// DaymarkCore (P1-scanner produces)
public struct NoteTokens: Sendable, Equatable { /* full shape in spec "New in DaymarkCore" */ }
public enum NoteTokenScanner {
    public static func scan(_ text: String) -> NoteTokens
    public static func scanLines(_ text: String, in lineRange: NSRange) -> NoteTokens
}
public enum TaskCheckboxToggler {
    public struct Edit: Sendable, Equatable { public let range: NSRange; public let replacement: String }
    public static func toggleEdit(in text: String, atLineContaining location: Int) -> Edit?
}

// AppState additions (P1-shell produces)
var isOpenLoopsOverlayPresented: Bool
var rolledOverCount: Int                       // launch rollover result; 0 when none
func toggleOpenLoopsOverlay()
func showCommandPalette(prefill: String?)      // nil = current behavior

// DesignTokens additions (P1-tokens produces)
DesignTokens.accentDeep (#4F634F), .checkboxBorder (#C9C5BE), .pillDueFill, .cardIslandFill, .dateTileFill
DesignMetrics.checkboxSize 16, .checkboxRadius 4, .pillRadius 4, .dateTileSize 48, .dateTileRadius 10,
    .windowWidth 860, .windowHeight 720, .minWindowWidth 620, .minWindowHeight 520
    (sidebarWidth and contextMarginWidth deleted)
DesignType.dateTileNumeral (26 semibold), .cardHeader (12 semibold), .pill (13)
```

Phase 3 packets run serially and read the merged code of their predecessors; their internal APIs are not pre-pinned here.

---

### Task 0: Phase 0 paperwork (orchestrator, no subagent)

**Files:**
- Modify: `docs/DECISIONS.md` (append ADR-012), `docs/ROADMAP.md` (insert M7, renumber Gmail to M8, iOS to M9)
- Create: `docs/orchestration/LEDGER.md`

- [ ] **Step 1:** ADR-012: Dynamic Note Surface direction (single pane, live-styled TextKit 2 editor with card islands, popover composer, margin/sidebar retirement, roadmap renumber). Match existing ADR entry format in `docs/DECISIONS.md`.
- [ ] **Step 2:** Ledger file with: model-tier table (empty), the jq measurement command over the session transcript JSONL summing `message.usage.output_tokens` grouped by `message.model`, gate log section, 20 percent Fable-share success bar.
- [ ] **Step 3:** slopcheck changed files; commit "Open Milestone 7: Dynamic Note Surface (ADR-012)".

### Task 1: P1-scanner, NoteTokenScanner + TaskCheckboxToggler (Sonnet, effort medium)

**Files:**
- Create: `Sources/DaymarkCore/NoteTokens/NoteTokens.swift`, `Sources/DaymarkCore/NoteTokens/NoteTokenScanner.swift`, `Sources/DaymarkCore/NoteTokens/TaskCheckboxToggler.swift`
- Test: `Tests/DaymarkCoreTests/NoteTokenScannerTests.swift`, `Tests/DaymarkCoreTests/TaskCheckboxTogglerTests.swift`

**Interfaces:** Produces the registry APIs verbatim. Consumes (read-only grammar references, never modified): `TaskParser`, `DynamicBlockParser`, `MarkdownFenceScanner`.

**Requirements:** Spec section "New in DaymarkCore" verbatim, including UTF-16 ranges, fence exclusion, TaskParser grammar parity (read `TaskParser` for the exact task and due-token grammar; divergence is a bug), M5 complete-pair and hash-aware region rules, CRLF handling.

- [ ] **Step 1:** Write the full failing test suite first. Required cases, minimum: headings H1-H3 with marker ranges; open/done/nested/indented tasks with box and text ranges; tag, wikilink, URL, due-token inline ranges; command lines for all four known commands; fenced block excludes every token type and respects fence type/length; well-formed region (range, innerRange, commandLineRange when adjacent); unpaired begin marker yields no region; hash-mismatched pair yields no region; adjacent regions; region at document start and end; CRLF document with correct ranges; emoji before a checkbox (UTF-16 offsets); empty string; toggler: open to done, done to open, indentation preserved, due metadata preserved, non-task line nil, inside well-formed region nil, inside fence nil, CRLF, emoji-heavy line.
- [ ] **Step 2:** `swift test --filter NoteTokenScannerTests` and `--filter TaskCheckboxTogglerTests`: all FAIL (types missing).
- [ ] **Step 3:** Implement to green, minimal.
- [ ] **Step 4:** `swift test --skip CommandTests`: full suite green (202 existing + new).
- [ ] **Step 5:** Report (no commit).

### Task 2: P1-tokens, design token additions (Haiku, effort low)

**Files:**
- Modify: `Daymark/UI/DesignSystem/DesignTokens.swift`, `Daymark/UI/DesignSystem/Components.swift`

**Interfaces:** Produces the registry token names verbatim. Also produces in `Components.swift`: `struct DateTile: View` (day numeral, spec "Day header" geometry), `struct TokenPill: View` (fill/text/optional SF Symbol leading glyph, `pillRadius`), checkbox style constants for the editor to consume (`checkboxSize`, stroke/fill colors).

**Requirements:** Spec "Visual spec: token additions" tables, exact hex. Delete `sidebarWidth`/`contextMarginWidth` and the old window numbers. Repurpose or replace the unused `TagChip`.

- [ ] **Step 1:** Apply additions/deletions. `swift build --product Daymark` compiles (callers of deleted metrics are P1-shell's problem only if P1-shell has merged; coordinate via orchestrator ordering, tokens merge first with old metrics kept until P1-shell deletes their last callers; if that ordering is impossible, keep deprecated aliases and note it in the report).
- [ ] **Step 2:** Report.

### Task 3: P1-shell, single-pane shell (Sonnet, effort medium)

**Files:**
- Modify: `Daymark/UI/RootView.swift`, `Daymark/UI/Today/TodayView.swift`, `Daymark/App/MenuCommands.swift`, `Daymark/App/AppState.swift`, `Daymark/App/SampleData.swift`, `Daymark/UI/CommandPalette/CommandPaletteView.swift` (action list + prefill only)
- Delete: `Daymark/UI/Sidebar/SidebarView.swift`

**Interfaces:** Consumes P1-tokens components. Produces the registry AppState members verbatim.

**Requirements:** Spec sections "Window and shell", "Day header", "Keyboard map" (⌘L added, ⌥⌘\ removed, ⌘Return reserved for Task 5, not bound here). Brief strip segments and click target; conflict banner restyle; status bar and dead chevrons removed; Open Loops presented as the spec's overlay (reusing `OpenLoopsView` internals as-is; restyle waits for Task 9). Margin state (`isContextMarginVisible` and plumbing) deleted, but `ContextMarginView` and its children stay in-tree until Phase 3 deletes them; RootView simply stops rendering them.

- [ ] **Step 1:** Implement. `swift build --product Daymark` green; `swift test --skip CommandTests` green.
- [ ] **Step 2:** Manual smoke per report: app launches, Today typable, header correct for today's date, ⌘L overlay opens/closes, palette opens with prefill hook, capture slip works.
- [ ] **Step 3:** Report.

### Task 4: P1-spike, card mechanism proof (Opus, effort high)

**Files:**
- Create: standalone throwaway SwiftPM package in the session scratchpad (`<scratchpad>/card-spike/`). Nothing in the repo tree.

**Requirements:** Spec packet table P1-spike verbatim: editable TextKit 2 `NSTextView`; marker-delimited region collapses to an interactive hosted SwiftUI card (a button that mutates card-local state must work); caret arrow-key entry reveals literal text; select-all + copy yields the literal text including markers; typing above/below the region stays flat (measure and report). Try custom `NSTextLayoutFragment` first, positioned-overlay-with-height-suppression second. Never touch `layoutManager`.

- [ ] **Step 1:** Build prototype(s), run, measure.
- [ ] **Step 2:** Structured verdict report: mechanism passed (fragment / overlay / neither), working core code sketch, sharp edges (selection, undo, resize, scrolling), latency numbers.

### Task 5 (gate): Phase 1 gate (orchestrator)

- [ ] Full Required Checks battery from `docs/PROGRESS.md` (library suite, both products, prebuilt CLI xctest slice).
- [ ] Read all four reports; verify P1-scanner test list covers the spec minimums; spike verdict selects the P3 mechanism (neither passing halts the milestone for redesign with Samay).
- [ ] slopcheck changed files; one commit per packet (add only owned paths); ledger update; dated `docs/PROGRESS.md` entry.

### Task 6: P2-editor, live rendering + interactions (Opus, effort high)

**Files:**
- Create: `Daymark/Editor/LiveRenderController.swift`
- Modify: `Daymark/Editor/NSTextViewRepresentable.swift`, `Daymark/Editor/DaymarkEditorView.swift` (if wiring requires)
- Delete: `Daymark/Editor/MarkdownHighlighter.swift`, `Daymark/Editor/CheckboxOverlay.swift`

**Interfaces:** Consumes `NoteTokenScanner`, `TaskCheckboxToggler`, P1-tokens styles, `AppState.showCommandPalette(prefill:)`.

**Requirements:** Spec "Live note body" token table row by row; checkbox conceal/draw/click/reveal contract; ⌘Return toggle; tag/wikilink click prefills palette; URL via link attribute; incremental scan (sync paragraph pass + 150ms debounced full pass); perf budgets with debug-build timing logs; the checkbox drawing-strategy latitude is granted, everything else is pinned. Undo must restore a toggle in one step. Reduce Motion: check fade, no spring.

- [ ] **Step 1:** Any new pure logic (for example attribute-run planning) goes in Core or a testable shell type with XCTest coverage written failing-first; AppKit glue is exercised by the manual matrix below.
- [ ] **Step 2:** Implement. `swift test --skip CommandTests` green; `swift build --product Daymark` green.
- [ ] **Step 3:** Manual matrix in report: click toggles + disk write within autosave window + single undo; caret in box reveals `[ ]`; ⌘Return parity; emoji-prefixed task toggles correctly; pills render per spec; fenced content renders plain; 5k-line generated note typing latency numbers.
- [ ] **Step 4:** Report.

### Task 7 (gate): Phase 2 gate (orchestrator + adversarial reviewer)

- [ ] Adversarial review packet (Opus, effort high, read-only): refute P2-editor. Targets: buffer mutation from render paths, TextKit 1 fallback trips, range drift (emoji/CRLF), undo grouping, latency claims, spec-table deviations. Findings verified before acting; confirmed findings go back to P2-editor as a fix packet.
- [ ] Mechanical battery; slopcheck; packet commit; ledger; PROGRESS entry.

### Task 8: Phase 3 pipeline (serial: P3-cards then P3-cardui then P3-codex)

**P3-cards (Opus, high).** Create `Daymark/Editor/CardIslands/` implementing the spike-proven mechanism: region collapse, hosted interactive card container, caret reveal/collapse, selection/copy literal-text rules. Consumes `NoteTokens.GeneratedRegion`. No degraded path for well-formed regions; malformed regions render literal (spec "Edge cases").

**P3-cardui (Sonnet, medium).** Create `Daymark/UI/Cards/DynamicBlockCardView.swift` per the spec card-states table (idle, preview pending, stale, source revealed; whole-note refresh semantics v1). Delete `Daymark/UI/ContextMargin/DynamicBlockRefreshView.swift`. Modify `AppState.swift`: per-card exposure of the existing preview/apply/stale state, receipt state stub for P3-codex.

**P3-codex (Sonnet, medium).** Create `Daymark/UI/Codex/CodexPopover.swift` + `Daymark/UI/Codex/ReceiptCard.swift` (popover at `firstRect(forCharacterRange:)`, receipt actions Reveal in Finder / Copy path / Create context bundle / Done, bundle offer rules unchanged). Delete `Daymark/UI/ContextMargin/ContextMarginView.swift`, `Daymark/UI/ContextMargin/CodexTaskComposerView.swift`, `Daymark/UI/Cards/SuggestionCardView.swift`.

- [ ] Each packet: suite + app build green, manual matrix in report, structured report; later packets read merged predecessor code.

### Task 9 (gate): Phase 3 gate (orchestrator + adversarial reviewer)

- [ ] Adversarial review (Opus, high) on P3-cards diff (selection/undo/resize/copy edge cases, staleness guard, malformed-marker honesty).
- [ ] Temp-workspace Dynamic Blocks check from Required Checks, driven end to end in the app where the check says "run apply".
- [ ] Codex chain walk: select, ⇧⌘C, edit, create, receipt, bundle, collision-safe paths, source untouched.
- [ ] Fable taste pass on screenshots. Mechanical battery, slopcheck, commits, ledger, PROGRESS entry.

### Task 10: Phase 4 polish (parallel: P4-restyle Sonnet low; P4-cleanup Haiku low; P4-docs Sonnet low)

**P4-restyle.** Modify `Daymark/UI/Slip/SlipPanelView.swift`, `Daymark/UI/CommandPalette/CommandPaletteView.swift` (visuals only), `Daymark/UI/OpenLoops/OpenLoopsView.swift` (overlay layout + row restyle with new checkbox/pill treatments). Behavior frozen.

**P4-cleanup.** Sweep dangling references to deleted views/metrics; audit every new animation against the spec motion table and Reduce Motion; run slopcheck across changed files. Delete only what the spec removed; report anything else.

**P4-docs.** Update `docs/DESIGN_SYSTEM.md`, `docs/INTERACTION_SPEC.md`, `README.md`, `docs/PROGRESS.md` (dated entry + WHERE WE LEFT OFF), `docs/PARKING_LOT.md` (spec "Parking lot additions" list verbatim).

- [ ] Each packet: suite green where applicable, structured report.

### Task 11 (gate): Final gate (orchestrator)

- [ ] Full Required Checks battery, including temp-workspace Dynamic Blocks check and `daymark doctor` read-only.
- [ ] Acceptance-criteria walk from the spec, item by item, against the running app.
- [ ] Fable taste gate on screenshots (spacing, hierarchy, hover, motion timing).
- [ ] Ledger final report: output tokens by tier, Fable share vs the 20 percent bar, gate log, all-Fable counterfactual estimate.
- [ ] Commits; `~/.progress.jsonl` append; offer push to Samay.

## Self-review notes

Spec coverage: every spec section maps to a task (shell/header Task 3; live body Task 6; cards Tasks 4/8; codex Task 8; restyles Task 10; tokens Task 2; scanner/toggler Task 1; edge cases distributed into the named packet requirements and gate walks; docs/ADR Tasks 0 and 10). Type consistency: all cross-packet names live in the Interface Registry and are quoted verbatim from the spec. Placeholders: none; where a packet's internals are intentionally unpinned (Phase 3 successors), the plan says to read the merged code, which is the doctrine's intent, not an omission.
