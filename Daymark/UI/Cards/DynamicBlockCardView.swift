import SwiftUI
import DaymarkCore

/// The dynamic-block card hosted inside a collapsed generated region. Renders the
/// idle / preview-pending / stale states from the spec's card-states table. Reveal is
/// two-way and tracked separately from the caret in `CardIslandController` (caret reveal and
/// the view-source toggle each hold their own bit; the region is revealed while either is
/// set). While revealed this view swaps to `stripView`, the thin header-only chrome the spec
/// calls for; the literal region text renders below it in the editor itself (see
/// `CardLayoutFragment`), and tapping the toggle again in the strip is how the user
/// re-collapses without moving the caret.
struct DynamicBlockCardView: View {
    let context: CardIslandContext
    let appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var regionHash: String { context.region.hash }

    private var pendingPreview: DynamicBlockCardPreview? {
        appState.dynamicBlockCardPreview(forRegionHash: regionHash)
    }

    var body: some View {
        if context.isRevealed {
            stripView
        } else {
            fullCardView
        }
    }

    private var fullCardView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            bodyContent
            if let preview = pendingPreview {
                footer(for: preview)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.cardIslandFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pendingPreview)
        .onChange(of: pendingPreview) { _, _ in context.notifyHeightChanged() }
    }

    /// Thin strip chrome shown while the region is revealed: title plus the active
    /// view-source toggle, no refresh control, no generated-at label, no body.
    private var stripView: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(CardIslandCommand.title(for: context.command))
                .font(DesignType.cardHeader)
                .tracking(0.5)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer(minLength: 8)
            sourceToggleButton
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(DesignTokens.cardIslandFill)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(CardIslandCommand.title(for: context.command))
                .font(DesignType.cardHeader)
                .tracking(0.5)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer(minLength: 8)
            if pendingPreview == nil, let generatedAt = appState.dynamicBlockGeneratedAt(forRegionHash: regionHash) {
                Text("generated \(Self.relativeFormatter.localizedString(for: generatedAt, relativeTo: Date()))")
                    .font(DesignType.metadata)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
            Button {
                Task { await appState.previewDynamicBlocksRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Refresh dynamic blocks")
            sourceToggleButton
        }
    }

    /// Always reflects the composite reveal state (spec requirement). Toggling it off clears
    /// only the user-driven half in the controller; if the caret is still inside the region
    /// this button stays active and the strip stays up, which is correct, not a bug.
    private var sourceToggleButton: some View {
        Button {
            context.setSourceRevealed(!context.isRevealed)
            context.notifyHeightChanged()
        } label: {
            Image(systemName: "curlybraces")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(context.isRevealed ? DesignTokens.accentDeep : DesignTokens.textTertiary)
        }
        .buttonStyle(.plain)
        .help("View source")
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let preview = pendingPreview {
            Text(CardMarkdownRenderer.attributedText(for: preview.incomingMarkdown))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 2)))
        } else {
            Text(CardMarkdownRenderer.attributedText(for: context.innerText))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(for preview: DynamicBlockCardPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.summaryText)
                .font(DesignType.metadata)
                .foregroundStyle(preview.canApply ? DesignTokens.textSecondary : DesignTokens.warning)
            HStack(spacing: 8) {
                Button("Apply") {
                    Task { await appState.applyDynamicBlocksRefresh() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!preview.canApply)
                .opacity(preview.canApply ? 1 : 0.55)
                Button("Cancel") {
                    appState.dismissDynamicBlocksRefresh()
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 2)))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

/// Derives a read-only styled `AttributedString` for a card body from `NoteTokenScanner`'s
/// output, mirroring the live editor's token catalog (headings, bullets, quotes, command
/// lines, tags, wikilinks, urls, due dates). Checkboxes render as static `☐`/`☑` glyphs
/// instead of the editor's interactive drawn control; generated content never round-trips
/// back into the buffer from here, so there is nothing to keep literal. Inline emphasis
/// (bold, italic, code spans) is not reproduced: `NoteTokenScanner` itself does not emit
/// those token kinds today (the live editor applies them via a separate regex pass that is
/// outside the Interface Registry), so there is no scanner output to derive them from.
enum CardMarkdownRenderer {
    static func attributedText(for markdown: String) -> AttributedString {
        guard !markdown.isEmpty else { return AttributedString("") }
        let ns = markdown as NSString
        let tokens = NoteTokenScanner.scan(markdown)
        var result = AttributedString()
        for (index, line) in tokens.lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            let inlineForLine = tokens.inlineTokens.filter { NSIntersectionRange($0.range, line.range).length > 0 }
            result += renderLine(line, inlineTokens: inlineForLine, text: ns)
        }
        return result
    }

    private enum Op {
        case checkbox(done: Bool)
        case strike
        case tag
        case wikilink
        case url
        case due(display: String)
        /// Machine text (rollover marker, provenance) is stripped from card bodies entirely:
        /// nothing that looks like code renders inside a card.
        case remove
    }

    private static func renderLine(_ line: NoteTokens.Line, inlineTokens: [NoteTokens.InlineToken], text: NSString) -> AttributedString {
        let lineLocation = line.range.location
        let originalPlain = text.substring(with: line.range) as NSString

        var ops: [(range: NSRange, op: Op)] = []
        if case .task(let done, _, let boxRange, let textRange) = line.kind {
            ops.append((relative(boxRange, to: lineLocation), .checkbox(done: done)))
            if done {
                ops.append((relative(textRange, to: lineLocation), .strike))
            }
        }
        for token in inlineTokens {
            let range = relative(token.range, to: lineLocation)
            switch token.kind {
            case .tag: ops.append((range, .tag))
            case .wikilink: ops.append((range, .wikilink))
            case .url: ops.append((range, .url))
            case .dueDate(let display): ops.append((range, .due(display: display)))
            case .rolloverMarker, .provenance: ops.append((range, .remove))
            case .codeSpan, .bold, .italic: break
            }
        }
        ops.sort { $0.range.location < $1.range.location }

        var plain = ""
        var runs: [(range: NSRange, op: Op)] = []
        var cursor = 0
        for entry in ops {
            guard entry.range.location >= cursor, entry.range.location + entry.range.length <= originalPlain.length else { continue }
            if entry.range.location > cursor {
                plain += originalPlain.substring(with: NSRange(location: cursor, length: entry.range.location - cursor))
            }
            let start = (plain as NSString).length
            let replacement: String
            switch entry.op {
            case .checkbox(let done): replacement = done ? "\u{2611}" : "\u{2610}"
            case .due(let display): replacement = "\u{1F550} \(display)"
            case .remove: replacement = ""
            case .strike, .tag, .wikilink, .url: replacement = originalPlain.substring(with: entry.range)
            }
            plain += replacement
            runs.append((NSRange(location: start, length: (replacement as NSString).length), entry.op))
            cursor = entry.range.location + entry.range.length
        }
        if cursor < originalPlain.length {
            plain += originalPlain.substring(with: NSRange(location: cursor, length: originalPlain.length - cursor))
        }

        var attributed = AttributedString(plain)
        attributed.font = DesignType.body
        attributed.foregroundColor = DesignTokens.textPrimary
        applyLineKindStyle(line.kind, to: &attributed)

        for run in runs {
            guard let attrRange = attributedRange(for: run.range, in: plain, attributed: attributed) else { continue }
            switch run.op {
            case .checkbox(let done):
                attributed[attrRange].foregroundColor = done ? DesignTokens.accent : DesignTokens.checkboxBorder
            case .strike:
                attributed[attrRange].strikethroughStyle = .single
                attributed[attrRange].foregroundColor = DesignTokens.textSecondary
            case .tag:
                attributed[attrRange].foregroundColor = DesignTokens.accentDeep
            case .wikilink:
                attributed[attrRange].foregroundColor = DesignTokens.accent
            case .url:
                attributed[attrRange].foregroundColor = DesignTokens.accent
                attributed[attrRange].underlineStyle = .single
            case .due:
                attributed[attrRange].foregroundColor = DesignTokens.textSecondary
                attributed[attrRange].backgroundColor = DesignTokens.pillDueFill
            case .remove:
                break
            }
        }
        return attributed
    }

    private static func applyLineKindStyle(_ kind: NoteTokens.LineKind, to attributed: inout AttributedString) {
        switch kind {
        case .heading(let level, _):
            attributed.font = headingFont(level: level)
        case .quote:
            attributed.foregroundColor = DesignTokens.textSecondary
            attributed.font = DesignType.body.italic()
        case .commandLine:
            attributed.font = DesignType.code
            attributed.foregroundColor = DesignTokens.accent
        case .task, .bullet, .fence, .body, .blank:
            break
        }
    }

    private static func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24, weight: .semibold)
        case 2: return .system(size: 19, weight: .semibold)
        case 3: return .system(size: 17, weight: .semibold)
        default: return .system(size: 16, weight: .semibold)
        }
    }

    private static func relative(_ range: NSRange, to lineLocation: Int) -> NSRange {
        NSRange(location: range.location - lineLocation, length: range.length)
    }

    private static func attributedRange(for nsRange: NSRange, in plain: String, attributed: AttributedString) -> Range<AttributedString.Index>? {
        guard let stringRange = Range(nsRange, in: plain),
              let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else {
            return nil
        }
        return lower..<upper
    }
}
