import SwiftUI
import DaymarkCore

/// Card body text, rebuilt only when its Markdown changes. Equatable on the Markdown so hover and
/// preview-state changes in the parent card never rescan the body.
struct CardMarkdownText: View, Equatable {
    let markdown: String

    var body: some View {
        CardMarkdownRenderer.text(for: markdown)
            .lineSpacing(8)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders generated Markdown for a card from `NoteTokenScanner`'s output, in the live editor's
/// visual language: SF Symbol checkboxes and due-date clocks, tinted tags and links, and machine
/// text (rollover markers, provenance) removed. Inline emphasis is not reproduced because the
/// scanner does not emit emphasis tokens.
@MainActor
enum CardMarkdownRenderer {
    private static var cache: [String: Text] = [:]
    private static let cacheLimit = 48

    static func text(for markdown: String) -> Text {
        if let cached = cache[markdown] { return cached }
        let built = compose(pieces(for: markdown))
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[markdown] = built
        return built
    }

    private enum Piece {
        case text(AttributedString)
        case symbol(name: String, color: Color, font: Font)
    }

    private enum Op {
        case checkbox(done: Bool)
        case tag
        case wikilink
        case url
        case due(display: String)
        case remove
    }

    /// Joins pieces with Text interpolation, the non-deprecated way to mix symbols into a Text.
    /// Adjacent text runs merge first so the nesting stays one level per symbol.
    private static func compose(_ pieces: [Piece]) -> Text {
        var merged: [Piece] = []
        for piece in pieces {
            if case .text(let next) = piece, case .text(let previous)? = merged.last {
                merged[merged.count - 1] = .text(previous + next)
            } else {
                merged.append(piece)
            }
        }
        var result: Text?
        for piece in merged {
            let next: Text
            switch piece {
            case .text(let attributed):
                next = Text(attributed)
            case .symbol(let name, let color, let font):
                next = Text(Image(systemName: name)).font(font).foregroundStyle(color)
            }
            if let previous = result {
                result = Text("\(previous)\(next)")
            } else {
                result = next
            }
        }
        return result ?? Text(verbatim: "")
    }

    private static func pieces(for markdown: String) -> [Piece] {
        guard !markdown.isEmpty else { return [] }
        let ns = markdown as NSString
        let tokens = NoteTokenScanner.scan(markdown)
        var pieces: [Piece] = []
        var tokenIndex = 0
        for (index, line) in tokens.lines.enumerated() {
            if index > 0 { pieces.append(.text(AttributedString("\n"))) }
            let lineEnd = line.range.location + line.range.length
            var inline: [NoteTokens.InlineToken] = []
            // Inline tokens arrive in document order, so one forward walk collects each line's.
            while tokenIndex < tokens.inlineTokens.count, tokens.inlineTokens[tokenIndex].range.location < lineEnd {
                if tokens.inlineTokens[tokenIndex].range.location >= line.range.location {
                    inline.append(tokens.inlineTokens[tokenIndex])
                }
                tokenIndex += 1
            }
            pieces.append(contentsOf: linePieces(line, inlineTokens: inline, text: ns))
        }
        return pieces
    }

    private static func linePieces(_ line: NoteTokens.Line, inlineTokens: [NoteTokens.InlineToken], text: NSString) -> [Piece] {
        let origin = line.range.location
        let lineText = text.substring(with: line.range) as NSString
        let style = LineStyle(kind: line.kind)

        var ops: [(range: NSRange, op: Op)] = []
        var marker: NSRange?
        var struck: NSRange?
        if case .task(let done, let markerRange, let boxRange, let textRange) = line.kind {
            marker = relative(markerRange, to: origin)
            ops.append((relative(boxRange, to: origin), .checkbox(done: done)))
            if done { struck = relative(textRange, to: origin) }
        }
        for token in inlineTokens {
            let range = relative(token.range, to: origin)
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

        // Strikethrough is a layer over whatever each run became, not an op of its own, so tokens
        // inside a completed task still get their pill, tint, or removal.
        func isStruck(_ range: NSRange) -> Bool {
            guard let struck else { return false }
            return range.location >= struck.location && range.location < struck.location + struck.length
        }

        func styled(_ string: String, range: NSRange, color: Color? = nil, font: Font? = nil, underline: Bool = false) -> Piece {
            var attributed = AttributedString(string)
            attributed.font = font ?? style.font
            attributed.foregroundColor = color ?? style.color
            if underline { attributed.underlineStyle = .single }
            if isStruck(range) {
                attributed.strikethroughStyle = .single
                attributed.foregroundColor = DesignTokens.textSecondary
            }
            return .text(attributed)
        }

        var pieces: [Piece] = []
        func emitPlain(from start: Int, to end: Int) {
            guard end > start else { return }
            // Split at the task marker and strike edges so each run takes exactly one style.
            var cuts = [start, end]
            for edge in [marker, struck].compactMap({ $0 }) {
                cuts.append(edge.location)
                cuts.append(edge.location + edge.length)
            }
            let sorted = Set(cuts.filter { $0 >= start && $0 <= end }).sorted()
            for (lower, upper) in zip(sorted, sorted.dropFirst()) where upper > lower {
                let range = NSRange(location: lower, length: upper - lower)
                let inMarker = marker.map { NSLocationInRange(lower, $0) } ?? false
                pieces.append(styled(lineText.substring(with: range), range: range, color: inMarker ? DesignTokens.textTertiary : nil))
            }
        }

        var cursor = 0
        for entry in ops {
            let range = entry.range
            guard range.location >= cursor, range.location + range.length <= lineText.length else { continue }
            emitPlain(from: cursor, to: range.location)
            let literal = lineText.substring(with: range)
            switch entry.op {
            case .checkbox(let done):
                pieces.append(.symbol(
                    name: done ? "checkmark.square" : "square",
                    color: DesignTokens.textSecondary,
                    font: style.font
                ))
            case .tag:
                pieces.append(styled(literal, range: range, color: DesignTokens.accentDeep))
            case .wikilink:
                pieces.append(styled(literal, range: range, color: DesignTokens.accent))
            case .url:
                pieces.append(styled(literal, range: range, color: DesignTokens.accent, underline: true))
            case .due(let display):
                pieces.append(.symbol(name: "clock", color: DesignTokens.textSecondary, font: DesignType.pill))
                pieces.append(styled("\u{2009}\(display)", range: range, color: DesignTokens.textSecondary, font: DesignType.pill))
            case .remove:
                break
            }
            cursor = range.location + range.length
        }
        emitPlain(from: cursor, to: lineText.length)
        return pieces
    }

    private struct LineStyle {
        var font: Font = DesignType.body
        var color: Color = DesignTokens.textPrimary

        init(kind: NoteTokens.LineKind) {
            switch kind {
            case .heading(let level, _):
                font = Self.headingFont(level: level)
            case .quote:
                font = DesignType.body.italic()
                color = DesignTokens.textSecondary
            case .commandLine:
                font = DesignType.code
                color = DesignTokens.textTertiary
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
    }

    private static func relative(_ range: NSRange, to origin: Int) -> NSRange {
        NSRange(location: range.location - origin, length: range.length)
    }
}
