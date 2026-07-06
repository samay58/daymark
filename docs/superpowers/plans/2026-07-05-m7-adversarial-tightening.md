# M7 Adversarial Tightening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten the M7 Dynamic Note Surface implementation without changing the product shape.

**Architecture:** Keep the app's TextKit 2 card-island approach. Move pure token-cache range shifting into `DaymarkCore` so it can be tested in the existing Core test target. Keep AppKit presentation, card layout, reveal animation, and popover UI inside the app shell.

**Tech Stack:** SwiftPM, Swift 5.9 package, macOS 14, SwiftUI, AppKit, TextKit 2, XCTest. Use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` and `--build-system native` for all SwiftPM commands.

## Global Constraints

- Current milestone: M7 Dynamic Note Surface final gate.
- Preserve one native `NSTextView` as the editor.
- Preserve TextKit 2 card islands as the dynamic-block presentation mechanism.
- Preserve Markdown as the readable source of truth.
- Preserve SQLite as a rebuildable projection.
- Preserve preview-before-write behavior for dynamic blocks and Codex artifacts.
- Do not add AI, network, Gmail, Calendar, app bundling, new product surfaces, or external dependencies.
- Do not touch `NSTextView.layoutManager`; TextKit 1 fallback is out of bounds.
- Do not rewrite the UI design, card chrome, glass treatment, typography, or motion.
- Do not revert user or prior-session changes. The new spec and this plan are currently untracked.
- Keep docs policy-clean: no literal em dash characters, no review-history labels in production comments.

---

## File Map

- `docs/superpowers/specs/2026-07-05-m7-adversarial-tightening.md`: source spec for this pass.
- `Tests/DaymarkCoreTests/NoteTokenScannerPerfTests.swift`: make perf budgets opt-in and add robust relative coverage.
- `Daymark/UI/Codex/CodexPopover.swift`: fix lifecycle race for an invisible popover host before window attach.
- `Daymark/UI/DesignSystem/Components.swift`: remove retired `.marginPanel()` layer.
- `Daymark/App/AppState.swift`: remove retired right-margin computed properties and stale comments.
- `docs/PROGRESS.md`: update current-truth lines that still describe right-margin panels as live architecture.
- `Sources/DaymarkCore/Tasks/TaskItem.swift`: add Core-owned due display grammar.
- `Sources/DaymarkCore/NoteTokens/NoteTokenScanner.swift`: consume Core due display grammar.
- `Daymark/UI/OpenLoops/OpenLoopsView.swift`: consume Core due display grammar and delete duplicated formatter.
- `Tests/DaymarkCoreTests/TaskItemTests.swift`: add due display tests.
- `Sources/DaymarkCore/NoteTokens/NoteTokenCacheReducer.swift`: new pure reducer for token/fence/range shifts.
- `Tests/DaymarkCoreTests/NoteTokenCacheReducerTests.swift`: regression tests for the reducer.
- `Daymark/Editor/LiveRenderController.swift`: delegate cache merge to the reducer and clean comments.
- `Daymark/Editor/LiveTextView.swift`, `Daymark/Editor/NSTextViewRepresentable.swift`, `Daymark/Editor/CardIslands/CardIslandController.swift`, `Daymark/UI/Today/TodayView.swift`, `Daymark/UI/DesignSystem/DesignTokens.swift`, `Tests/DaymarkCoreTests/DailyNoteTests.swift`, `Tests/DaymarkCoreTests/NoteTokenScannerTests.swift`: comment and prose cleanup targets.

## Task 1: Make The Default Verification Gate Reliable

**Files:**
- Modify: `Tests/DaymarkCoreTests/NoteTokenScannerPerfTests.swift`

**Interfaces:**
- Consumes: `NoteTokenScanner.scan(_:)`, `NoteTokenScanner.scanLines(_:in:)`, `NoteTokenScanner.scanLines(_:in:fence:)`, `MarkdownFenceScanner`.
- Produces: default-green perf characterization tests; strict fixed budgets only under `DAYMARK_PERF=1`.

- [ ] **Step 1: Verify current default gate behavior**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --skip CommandTests --build-system native
```

Expected after this task: pass. If it fails before edits on only `NoteTokenScannerPerfTests`, continue. If it fails elsewhere, stop and investigate because this plan assumes the functional suite is otherwise sound.

- [ ] **Step 2: Add relative regression coverage**

Edit `Tests/DaymarkCoreTests/NoteTokenScannerPerfTests.swift`. Keep the existing `DAYMARK_PERF` opt-in flag. Replace the document-end tests with a single relative test or add this new test near the existing document-end tests:

```swift
func testFenceSuppliedScanAvoidsPrefixWalkAtDocumentEnd() {
    let text = representativeNote(lines: 5000)
    let ns = text as NSString
    let lastLine = ns.lineRange(for: NSRange(location: ns.length - 1, length: 0))
    let fence = MarkdownFenceScanner()

    var defaultBest = Double.greatestFiniteMagnitude
    var suppliedBest = Double.greatestFiniteMagnitude
    for _ in 0..<10 {
        var started = CFAbsoluteTimeGetCurrent()
        _ = NoteTokenScanner.scanLines(text, in: lastLine)
        defaultBest = min(defaultBest, (CFAbsoluteTimeGetCurrent() - started) * 1000)

        started = CFAbsoluteTimeGetCurrent()
        _ = NoteTokenScanner.scanLines(text, in: lastLine, fence: fence)
        suppliedBest = min(suppliedBest, (CFAbsoluteTimeGetCurrent() - started) * 1000)
    }

    NSLog("[perf] document-end scanLines default best %.4f ms; fence-supplied best %.4f ms", defaultBest, suppliedBest)
    XCTAssertLessThan(suppliedBest, defaultBest * 0.5)
}
```

- [ ] **Step 3: Clean review-history wording in this file**

Replace comments that mention `Finding 1` or old measurement anecdotes with invariant comments. Keep the meaning:

```swift
// The default scanLines overload derives fence state by walking from the document start.
// That path stays correct for generic callers, but it is not the editor's per-keystroke path.
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter NoteTokenScannerPerfTests --build-system native
```

Expected: pass by default, with perf metrics printed.

- [ ] **Step 5: Run the default library suite**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --skip CommandTests --build-system native
```

Expected: pass.

## Task 2: Fix Codex Popover Window-Attach Race

**Files:**
- Modify: `Daymark/UI/Codex/CodexPopover.swift`

**Interfaces:**
- Consumes: `AppState.isCodexPopoverPresented`, `AppState.codexAnchorScreenRect`, `AppState.dismissCodexTaskDraft()`.
- Produces: `PopoverAnchorView` with `viewDidMoveToWindow` retry and a single coordinator presentation path.

- [ ] **Step 1: Replace the plain host view**

In `CodexPopoverHost`, replace:

```swift
func makeNSView(context: Context) -> NSView { NSView() }
```

with:

```swift
func makeNSView(context: Context) -> PopoverAnchorView {
    let view = PopoverAnchorView()
    view.onWindowChange = { [weak coordinator = context.coordinator, weak view] in
        guard let view else { return }
        coordinator?.hostDidMoveToWindow(view)
    }
    return view
}
```

Add this private class below `CodexPopoverHost`:

```swift
private final class PopoverAnchorView: NSView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }
}
```

- [ ] **Step 2: Store pending presentation state in the coordinator**

Inside `Coordinator`, add:

```swift
private weak var hostRef: NSView?
```

Replace `sync(host:appState:)` with this shape:

```swift
func sync(host: NSView, appState: AppState) {
    hostRef = host
    appStateRef = appState
    if appState.isCodexPopoverPresented {
        attemptPresent()
    } else if let popover {
        isClosingProgrammatically = true
        popover.performClose(nil)
    }
}

func hostDidMoveToWindow(_ host: NSView) {
    hostRef = host
    attemptPresent()
}
```

- [ ] **Step 3: Add the single attempt path**

Replace the current `present(from:appState:)` call path with:

```swift
private func attemptPresent() {
    guard popover == nil else { return }
    guard let appState = appStateRef, appState.isCodexPopoverPresented else { return }
    guard let host = hostRef, let window = host.window else { return }

    let screenRect = appState.codexAnchorScreenRect ?? window.frame
    let localRect = host.convert(window.convertFromScreen(screenRect), from: nil)

    let created = NSPopover()
    created.behavior = .semitransient
    created.delegate = self
    created.contentSize = NSSize(width: 380, height: 480)
    created.contentViewController = NSHostingController(rootView: CodexComposerForm(appState: appState))
    created.show(relativeTo: localRect, of: host, preferredEdge: .maxY)
    popover = created
}
```

Delete the old `present(from:appState:)` method.

- [ ] **Step 4: Build the app product**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product Daymark --build-system native
```

Expected: pass.

- [ ] **Step 5: Manually smoke the lifecycle when possible**

Launch the app, immediately trigger the Codex composer, and confirm the popover appears once. Cancel, click outside, Esc, and Create should preserve current state behavior.

## Task 3: Remove Retired Right-Margin Layers

**Files:**
- Modify: `Daymark/UI/DesignSystem/Components.swift`
- Modify: `Daymark/App/AppState.swift`
- Modify: `docs/PROGRESS.md`

**Interfaces:**
- Consumes: existing receipt, context bundle, dynamic block state.
- Produces: no live-code references to `.marginPanel()` or retired right-margin computed properties.

- [ ] **Step 1: Confirm no live callers**

Run:

```bash
rg -n "marginPanel|MarginPanel|showsDynamicBlockRefreshPanel|showsContextBundlePanel|createdCodexTaskRelativePath|isDynamicBlockPreviewStale" Daymark Sources Tests docs/PROGRESS.md
```

Expected before edits: hits in `Components.swift`, `AppState.swift`, and current-truth docs.

- [ ] **Step 2: Delete the old modifier**

Remove `MarginPanel` and the `marginPanel()` extension from `Daymark/UI/DesignSystem/Components.swift`. Keep `GlassSurface`, `GlassMaterialView`, and `glassSurface()`.

- [ ] **Step 3: Delete retired computed properties**

Remove these from `Daymark/App/AppState.swift`:

```swift
var createdCodexTaskRelativePath: String? { createdCodexTask?.relativePath }
var isDynamicBlockPreviewStale: Bool { ... }
var showsDynamicBlockRefreshPanel: Bool { ... }
var showsContextBundlePanel: Bool { ... }
```

Also remove or rewrite comments that refer to the context margin as a live render path.

- [ ] **Step 4: Update current-truth docs**

In `docs/PROGRESS.md`, replace the line that says:

```markdown
- One helper, `WorkspaceRoot.existingMarkdownRelativePaths(under:)`, backs collision-safe naming for tasks and bundles across the writers, the CLI, and `AppState`. The right-margin panels share `ReadOnlyField` and the `marginPanel()` modifier from `Components.swift`.
```

with:

```markdown
- One helper, `WorkspaceRoot.existingMarkdownRelativePaths(under:)`, backs collision-safe naming for tasks and bundles across the writers, the CLI, and `AppState`. M7 retired the right-margin panels; Codex now uses a selection-anchored popover plus receipt card, and floating surfaces share `glassSurface()` where native material is intended.
```

- [ ] **Step 5: Verify removal**

Run:

```bash
rg -n "marginPanel|MarginPanel|showsDynamicBlockRefreshPanel|showsContextBundlePanel|createdCodexTaskRelativePath|isDynamicBlockPreviewStale" Daymark Sources Tests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product Daymark --build-system native
```

Expected: `rg` has no live-code hits; build passes.

## Task 4: Centralize Due-Date Display Grammar

**Files:**
- Modify: `Sources/DaymarkCore/Tasks/TaskItem.swift`
- Modify: `Sources/DaymarkCore/NoteTokens/NoteTokenScanner.swift`
- Modify: `Daymark/UI/OpenLoops/OpenLoopsView.swift`
- Create: `Tests/DaymarkCoreTests/TaskItemTests.swift`

**Interfaces:**
- Produces: `TaskItem.Due.displayText(calendar:) -> String`.
- Consumes: `ISODate.date(from:calendar:)`.

- [ ] **Step 1: Add focused failing tests**

Create `Tests/DaymarkCoreTests/TaskItemTests.swift`:

```swift
import XCTest
@testable import DaymarkCore

final class TaskItemTests: XCTestCase {
    func testDueDisplayTextForRelativeTokens() {
        XCTAssertEqual(TaskItem.Due.today.displayText(), "Today")
        XCTAssertEqual(TaskItem.Due.tomorrow.displayText(), "Tomorrow")
    }

    func testDueDisplayTextForISODate() {
        XCTAssertEqual(TaskItem.Due.date("2026-07-08").displayText(), "Jul 8")
    }

    func testDueDisplayTextFallsBackToRawDateToken() {
        XCTAssertEqual(TaskItem.Due.date("not-a-date").displayText(), "not-a-date")
    }
}
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter TaskItemTests --build-system native
```

Expected before implementation: fail because `displayText()` is missing.

- [ ] **Step 2: Implement the Core helper**

In `Sources/DaymarkCore/Tasks/TaskItem.swift`, add this inside `public enum Due`:

```swift
public func displayText(calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
    switch self {
    case .today:
        return "Today"
    case .tomorrow:
        return "Tomorrow"
    case .date(let iso):
        guard let date = ISODate.date(from: iso, calendar: calendar) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 3: Use the helper in `NoteTokenScanner`**

In `Sources/DaymarkCore/NoteTokens/NoteTokenScanner.swift`, change:

```swift
let computed = TaskItem.Due(token: value).map(humanize)
```

to:

```swift
let computed = TaskItem.Due(token: value)?.displayText()
```

Delete `humanizeCalendar`, `humanizeFormatter`, and `humanize(_:)` from `NoteTokenScanner`.

- [ ] **Step 4: Use the helper in Open Loops**

In `Daymark/UI/OpenLoops/OpenLoopsView.swift`, change:

```swift
text: Self.dueDisplay(due),
```

to:

```swift
text: due.displayText(),
```

Delete the private `dueFormatter` and `dueDisplay(_:)` members from `OpenLoopTaskRow`.

- [ ] **Step 5: Run focused and related tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter TaskItemTests --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter NoteTokenScannerTests --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter OpenLoopsTests --build-system native
```

Expected: all pass.

## Task 5: Extract And Test The Pure Note Token Cache Reducer

**Files:**
- Create: `Sources/DaymarkCore/NoteTokens/NoteTokenCacheReducer.swift`
- Create: `Tests/DaymarkCoreTests/NoteTokenCacheReducerTests.swift`
- Modify: `Daymark/Editor/LiveRenderController.swift`

**Interfaces:**
- Produces: `NoteTokenCacheReducer.merge(state:rescanned:editedRange:) -> NoteTokenCacheReducer.Result`.
- Produces: `NoteTokenCacheReducer.shiftKeyedRanges(_:editStart:oldParagraphEnd:delta:)`.
- Consumes: `NoteTokens`, `MarkdownFenceScanner`, `NSRange`.

- [ ] **Step 1: Create the reducer tests first**

Create `Tests/DaymarkCoreTests/NoteTokenCacheReducerTests.swift` with tests shaped around the current merge semantics:

```swift
import XCTest
@testable import DaymarkCore

final class NoteTokenCacheReducerTests: XCTestCase {
    func testInsertLineAboveRegionShiftsRegionAndFenceState() {
        let before = """
        intro
        /daymark open-loops
        <!-- daymark:block-begin abc -->
        generated
        <!-- daymark:block-end abc -->
        tail
        """
        let after = """
        intro
        inserted
        /daymark open-loops
        <!-- daymark:block-begin abc -->
        generated
        <!-- daymark:block-end abc -->
        tail
        """
        let nsAfter = after as NSString
        let insertedLine = nsAfter.lineRange(for: NSRange(location: nsAfter.range(of: "inserted").location, length: 0))
        let rescanned = NoteTokenScanner.scanLines(after, in: insertedLine)
        let state = NoteTokenCacheReducer.State(
            tokens: NoteTokenScanner.scan(before),
            lineFenceStates: NoteTokenCacheReducer.fenceStates(for: before)
        )

        let result = NoteTokenCacheReducer.merge(state: state, rescanned: rescanned, editedRange: insertedLine)
        XCTAssertEqual(result.state.tokens, NoteTokenScanner.scan(after))
        XCTAssertEqual(result.delta, insertedLine.length)
    }

    func testDeleteLineAboveRegionShiftsRegionAndFenceState() {
        let before = "intro\nremove me\n/daymark open-loops\n<!-- daymark:block-begin abc -->\ngenerated\n<!-- daymark:block-end abc -->\n"
        let after = "intro\n/daymark open-loops\n<!-- daymark:block-begin abc -->\ngenerated\n<!-- daymark:block-end abc -->\n"
        let nsAfter = after as NSString
        let changedLine = nsAfter.lineRange(for: NSRange(location: nsAfter.range(of: "/daymark").location, length: 0))
        let rescanned = NoteTokenScanner.scanLines(after, in: changedLine)
        let oldRange = NSRange(location: ("intro\n" as NSString).length, length: ("remove me\n" as NSString).length + changedLine.length)
        let state = NoteTokenCacheReducer.State(
            tokens: NoteTokenScanner.scan(before),
            lineFenceStates: NoteTokenCacheReducer.fenceStates(for: before)
        )

        let result = NoteTokenCacheReducer.merge(state: state, rescanned: rescanned, editedRange: oldRange)
        XCTAssertEqual(result.state.tokens, NoteTokenScanner.scan(after))
        XCTAssertLessThan(result.delta, 0)
    }

    func testShiftKeyedRangesDropsEditedRangeAndMovesFollowingRanges() {
        let ranges = [
            NoteTokenCacheReducer.KeyedRange(key: 5, range: NSRange(location: 5, length: 3)),
            NoteTokenCacheReducer.KeyedRange(key: 20, range: NSRange(location: 20, length: 4)),
            NoteTokenCacheReducer.KeyedRange(key: 40, range: NSRange(location: 40, length: 2))
        ]

        let shifted = NoteTokenCacheReducer.shiftKeyedRanges(
            ranges,
            editStart: 10,
            oldParagraphEnd: 30,
            delta: 7
        )

        XCTAssertEqual(shifted.map(\\.key), [5, 47])
        XCTAssertEqual(shifted.map(\\.range.location), [5, 47])
    }

    func testFenceMarkerEditRequiresFullPass() {
        let before = "```\n- [ ] hidden\n```\n- [ ] visible\n"
        let after = "`\n- [ ] hidden\n```\n- [ ] visible\n"
        let incremental = NoteTokenCacheReducer.canMergeIncrementally(
            text: after,
            editedRange: NSRange(location: 0, length: 1)
        )
        XCTAssertFalse(incremental)
        XCTAssertNotEqual(NoteTokenScanner.scan(before), NoteTokenScanner.scan(after))
    }
}
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter NoteTokenCacheReducerTests --build-system native
```

Expected before implementation: fail because `NoteTokenCacheReducer` is missing.

- [ ] **Step 2: Implement the Core reducer**

Create `Sources/DaymarkCore/NoteTokens/NoteTokenCacheReducer.swift`:

```swift
import Foundation

public enum NoteTokenCacheReducer {
    public struct LineFenceState: Sendable {
        public let location: Int
        public let fence: MarkdownFenceScanner

        public init(location: Int, fence: MarkdownFenceScanner) {
            self.location = location
            self.fence = fence
        }
    }

    public struct KeyedRange: Sendable, Equatable {
        public let key: Int
        public let range: NSRange

        public init(key: Int, range: NSRange) {
            self.key = key
            self.range = range
        }
    }

    public struct State: Sendable {
        public let tokens: NoteTokens
        public let lineFenceStates: [LineFenceState]

        public init(tokens: NoteTokens, lineFenceStates: [LineFenceState]) {
            self.tokens = tokens
            self.lineFenceStates = lineFenceStates
        }
    }

    public struct Result: Sendable {
        public let state: State
        public let oldParagraphEnd: Int
        public let delta: Int
    }

    public static func merge(state: State, rescanned tokens: NoteTokens, editedRange: NSRange) -> Result {
        let cachedLines = state.tokens.lines
        let linePrefixEnd = lowerBound(cachedLines, location: editedRange.location) { $0.range.location }
        var lineSuffixStart = linePrefixEnd
        while lineSuffixStart < cachedLines.count, cachedLines[lineSuffixStart].range.location <= editedRange.location {
            lineSuffixStart += 1
        }

        let oldParagraphEnd = lineSuffixStart < cachedLines.count
            ? cachedLines[lineSuffixStart].range.location
            : editedRange.location + editedRange.length
        let delta = editedRange.location + editedRange.length - oldParagraphEnd

        var lines: [NoteTokens.Line] = []
        lines.reserveCapacity(cachedLines.count + tokens.lines.count)
        lines.append(contentsOf: cachedLines[..<linePrefixEnd])
        lines.append(contentsOf: tokens.lines)
        appendShiftedTail(cachedLines, from: lineSuffixStart, delta: delta, into: &lines)

        let cachedInline = state.tokens.inlineTokens
        let inlinePrefixEnd = lowerBound(cachedInline, location: editedRange.location) { $0.range.location }
        let inlineSuffixStart = lowerBound(cachedInline, location: oldParagraphEnd) { $0.range.location }
        var inline: [NoteTokens.InlineToken] = []
        inline.reserveCapacity(cachedInline.count + tokens.inlineTokens.count)
        inline.append(contentsOf: cachedInline[..<inlinePrefixEnd])
        inline.append(contentsOf: tokens.inlineTokens)
        appendShiftedTail(cachedInline, from: inlineSuffixStart, delta: delta, into: &inline)

        let regions = delta == 0
            ? state.tokens.regions
            : state.tokens.regions.map { $0.range.location >= oldParagraphEnd ? shifted($0, by: delta) : $0 }

        let fenceStates = delta == 0
            ? state.lineFenceStates
            : state.lineFenceStates.map {
                $0.location > editedRange.location
                    ? LineFenceState(location: $0.location + delta, fence: $0.fence)
                    : $0
            }

        return Result(
            state: State(tokens: NoteTokens(lines: lines, inlineTokens: inline, regions: regions), lineFenceStates: fenceStates),
            oldParagraphEnd: oldParagraphEnd,
            delta: delta
        )
    }

    public static func shiftKeyedRanges(_ ranges: [KeyedRange], editStart: Int, oldParagraphEnd: Int, delta: Int) -> [KeyedRange] {
        guard delta != 0 else { return ranges }
        return ranges.compactMap { item in
            if item.key < editStart { return item }
            if item.key < oldParagraphEnd { return nil }
            return KeyedRange(key: item.key + delta, range: shifted(item.range, by: delta))
        }
    }

    public static func fenceStates(for text: String) -> [LineFenceState] {
        let nsText = text as NSString
        var result: [LineFenceState] = []
        var fence = MarkdownFenceScanner()
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byLines) { substring, range, _, _ in
            result.append(LineFenceState(location: range.location, fence: fence))
            let content = substring ?? ""
            let leadingCount = content.prefix { $0 == " " || $0 == "\t" }.count
            _ = fence.consume(trimmedLine: String(content.dropFirst(leadingCount)))
        }
        return result
    }

    public static func canMergeIncrementally(text: String, editedRange: NSRange) -> Bool {
        !containsFenceMarker(text as NSString, in: editedRange)
    }

    private static func appendShiftedTail<T>(_ items: [T], from start: Int, delta: Int, into output: inout [T]) {
        guard start < items.count else { return }
        if delta == 0 {
            output.append(contentsOf: items[start...])
        } else {
            for index in start..<items.count {
                if let line = items[index] as? NoteTokens.Line {
                    output.append(shifted(line, by: delta) as! T)
                } else if let token = items[index] as? NoteTokens.InlineToken {
                    output.append(shifted(token, by: delta) as! T)
                }
            }
        }
    }

    private static func shifted(_ line: NoteTokens.Line, by delta: Int) -> NoteTokens.Line {
        let newKind: NoteTokens.LineKind
        switch line.kind {
        case .heading(let level, let markerRange):
            newKind = .heading(level: level, markerRange: shifted(markerRange, by: delta))
        case .task(let done, let markerRange, let boxRange, let textRange):
            newKind = .task(done: done, markerRange: shifted(markerRange, by: delta), boxRange: shifted(boxRange, by: delta), textRange: shifted(textRange, by: delta))
        case .bullet(let markerRange):
            newKind = .bullet(markerRange: shifted(markerRange, by: delta))
        case .quote, .commandLine, .fence, .body, .blank:
            newKind = line.kind
        }
        return NoteTokens.Line(range: shifted(line.range, by: delta), kind: newKind)
    }

    private static func shifted(_ token: NoteTokens.InlineToken, by delta: Int) -> NoteTokens.InlineToken {
        NoteTokens.InlineToken(range: shifted(token.range, by: delta), kind: token.kind)
    }

    private static func shifted(_ region: NoteTokens.GeneratedRegion, by delta: Int) -> NoteTokens.GeneratedRegion {
        NoteTokens.GeneratedRegion(
            hash: region.hash,
            range: shifted(region.range, by: delta),
            innerRange: shifted(region.innerRange, by: delta),
            commandLineRange: region.commandLineRange.map { shifted($0, by: delta) }
        )
    }

    private static func shifted(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    private static func lowerBound<T>(_ items: [T], location: Int, _ key: (T) -> Int) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if key(items[mid]) < location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func containsFenceMarker(_ ns: NSString, in range: NSRange) -> Bool {
        let clamped = NSRange(location: max(0, min(range.location, ns.length)), length: max(0, min(range.length, ns.length - max(0, min(range.location, ns.length)))))
        var index = clamped.location
        let end = clamped.location + clamped.length
        while index < end {
            let ch = ns.character(at: index)
            if ch == 0x20 || ch == 0x09 { index += 1; continue }
            guard ch == UInt16(UnicodeScalar("`").value) || ch == UInt16(UnicodeScalar("~").value) else { return false }
            var count = 0
            var probe = index
            while probe < end, ns.character(at: probe) == ch {
                count += 1
                probe += 1
            }
            return count >= 3
        }
        return false
    }
}
```

If Swift rejects the generic `appendShiftedTail` casts, split it into two overloads:

```swift
private static func appendShiftedLines(...)
private static func appendShiftedInlineTokens(...)
```

Prefer the overloads if they are clearer after the first compile.

- [ ] **Step 3: Wire the app controller to the reducer**

In `Daymark/Editor/LiveRenderController.swift`:

- Replace `lineFenceStates: [(location: Int, fence: MarkdownFenceScanner)]` with `[NoteTokenCacheReducer.LineFenceState]`.
- Replace `Self.fenceStates(for: text)` calls with `NoteTokenCacheReducer.fenceStates(for: text)`.
- Update `fenceStateEntering(_:)` to read `.location` and `.fence`.
- In `mergeIntoCache`, delegate line, inline, region, and fence-state shifts to `NoteTokenCacheReducer.merge(...)`.
- Keep `textVersion += 1` in the controller.
- Keep reveal-fade shifting in the controller, using `result.oldParagraphEnd` and `result.delta`.

The controller body should end up with this shape:

```swift
let result = NoteTokenCacheReducer.merge(
    state: NoteTokenCacheReducer.State(tokens: cachedTokens, lineFenceStates: lineFenceStates),
    rescanned: tokens,
    editedRange: editedRange
)
cachedTokens = result.state.tokens
lineFenceStates = result.state.lineFenceStates
shiftRevealFades(editStart: editedRange.location, oldParagraphEnd: result.oldParagraphEnd, delta: result.delta)
textVersion += 1
```

- [ ] **Step 4: Extract local reveal-fade shifting**

Add a private helper in `LiveRenderController`:

```swift
private func shiftRevealFades(editStart: Int, oldParagraphEnd: Int, delta: Int) {
    guard delta != 0, !revealFades.isEmpty else { return }
    let ranges = revealFades.map { NoteTokenCacheReducer.KeyedRange(key: $0.key, range: $0.value.range) }
    let shifted = NoteTokenCacheReducer.shiftKeyedRanges(ranges, editStart: editStart, oldParagraphEnd: oldParagraphEnd, delta: delta)
    var next: [Int: RevealFade] = [:]
    next.reserveCapacity(shifted.count)
    for item in shifted {
        let oldKey = item.key - delta
        guard var fade = revealFades[oldKey] ?? revealFades[item.key] else { continue }
        fade.range = item.range
        next[item.key] = fade
    }
    revealFades = next
}
```

Check the `oldKey` lookup carefully during implementation. If a pre-edit key before `editStart` is unchanged, the fallback `revealFades[item.key]` must preserve it.

- [ ] **Step 5: Run reducer and app build checks**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter NoteTokenCacheReducerTests --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product Daymark --build-system native
```

Expected: both pass.

## Task 6: Clean Production Comments And Prose Policy

**Files:**
- Modify: `Daymark/Editor/LiveRenderController.swift`
- Modify: `Daymark/Editor/LiveTextView.swift`
- Modify: `Daymark/Editor/NSTextViewRepresentable.swift`
- Modify: `Daymark/Editor/CardIslands/CardIslandController.swift`
- Modify: `Daymark/UI/Today/TodayView.swift`
- Modify: `Daymark/UI/DesignSystem/DesignTokens.swift`
- Modify: `Tests/DaymarkCoreTests/DailyNoteTests.swift`
- Modify: `Tests/DaymarkCoreTests/NoteTokenScannerTests.swift`
- Modify: `Tests/DaymarkCoreTests/NoteTokenScannerPerfTests.swift`

**Interfaces:**
- Produces: comments that explain durable invariants, not review history.

- [ ] **Step 1: Run the review-history scan**

Run:

```bash
rg -n "Bug [0-9]|Finding [0-9]|measured at|review pass" Daymark Sources Tests
```

- [ ] **Step 2: Rewrite production comments**

Use this style:

```swift
// Retrying is safe because attach is idempotent; the anchor may not have a window during makeNSView.
```

Avoid this style:

```swift
// Bug 2: ...
```

- [ ] **Step 3: Fix the literal em dash test**

In `Tests/DaymarkCoreTests/DailyNoteTests.swift`, change the literal character assertion to:

```swift
XCTAssertFalse(template.contains("\u{2014}"), "no em dash in generated content")
```

- [ ] **Step 4: Run policy scans**

Run:

```bash
rg -n "Bug [0-9]|Finding [0-9]|measured at|review pass" Daymark Sources Tests
rg -n "$(printf '\\u2014')" AGENTS.md CLAUDE.md Daymark Sources Tests docs README.md
```

Expected: no hits. Also run the prose kill-list terms from `AGENTS.md` without pasting that pattern into tracked docs. Do not add a literal em dash to any file while writing the check.

## Final Verification

- [ ] **Step 1: Check working tree**

```bash
git status --short
```

- [ ] **Step 2: Run library tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --skip CommandTests --build-system native
```

- [ ] **Step 3: Build both products**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product Daymark --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product daymark --build-system native
```

- [ ] **Step 4: Run CLI command tests through the prebuilt bundle**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-tests --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --product daymark --build-system native
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun xctest .build/arm64-apple-macosx/debug/DaymarkPackageTests.xctest
```

- [ ] **Step 5: Run read-only doctor**

```bash
.build/arm64-apple-macosx/debug/daymark doctor
```

- [ ] **Step 6: Run the temp-workspace Dynamic Blocks check**

Use the current checklist in `docs/PROGRESS.md`: create prior and current daily notes in a temp root, add project source, task spec, and context bundle, include `/daymark open-loops`, `/daymark source-list #tag`, `/daymark codex-context #tag`, and `/daymark weekly-review`, verify dry-run writes nothing, apply is idempotent, user text is preserved, generated checkboxes do not feed back, cache deletion recovers, and doctor remains clean.

## Handoff Notes

- Packet A may already be partially implemented in the current tree. Verify before editing.
- The reducer code block above is a guide, not a command to paste blindly. Compile early and prefer two typed helper overloads over generic casts if the compiler complains.
- Do not close M7 in docs. This pass tightens implementation before Samay's acceptance walk.
- Do not commit unless Samay asks for a commit. If committing later, commit per coherent packet after green checks.
