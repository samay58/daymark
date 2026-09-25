import Foundation

public struct NoteTokens: Sendable, Equatable {
    public struct GeneratedRegion: Sendable, Equatable {
        public let hash: String
        public let range: NSRange
        public let innerRange: NSRange
        public let commandLineRange: NSRange?

        public init(hash: String, range: NSRange, innerRange: NSRange, commandLineRange: NSRange?) {
            self.hash = hash
            self.range = range
            self.innerRange = innerRange
            self.commandLineRange = commandLineRange
        }
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

        public init(range: NSRange, kind: LineKind) {
            self.range = range
            self.kind = kind
        }
    }

    public enum InlineKind: Sendable, Equatable {
        case tag
        case wikilink
        case url
        case dueDate(display: String)
        /// The `<!-- daymark-rollover:<hash> -->` dedup marker on a rolled-over line. Literal
        /// on disk, concealed in the live render, revealed on caret/selection intersect.
        case rolloverMarker
        /// The `(from <path>:<line>)` provenance parenthetical on a rolled-over line. Same
        /// conceal-and-reveal treatment as the marker.
        case provenance
    }

    public struct InlineToken: Sendable, Equatable {
        public let range: NSRange
        public let kind: InlineKind

        public init(range: NSRange, kind: InlineKind) {
            self.range = range
            self.kind = kind
        }
    }

    public let lines: [Line]
    public let inlineTokens: [InlineToken]
    public let regions: [GeneratedRegion]

    public init(lines: [Line], inlineTokens: [InlineToken], regions: [GeneratedRegion]) {
        self.lines = lines
        self.inlineTokens = inlineTokens
        self.regions = regions
    }
}
