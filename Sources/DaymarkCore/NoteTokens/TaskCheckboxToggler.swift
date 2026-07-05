import Foundation

public enum TaskCheckboxToggler {
    public struct Edit: Sendable, Equatable {
        public let range: NSRange
        public let replacement: String

        public init(range: NSRange, replacement: String) {
            self.range = range
            self.replacement = replacement
        }
    }

    public static func toggleEdit(in text: String, atLineContaining location: Int) -> Edit? {
        let tokens = NoteTokenScanner.scan(text)

        guard let line = tokens.lines.first(where: { line in
            location >= line.range.location && location <= line.range.location + line.range.length
        }) else {
            return nil
        }

        guard case .task(let done, _, let boxRange, _) = line.kind else { return nil }

        for region in tokens.regions where NSIntersectionRange(region.range, line.range).length > 0 {
            return nil
        }

        let interior = NSRange(location: boxRange.location + 1, length: 1)
        let replacement = done ? " " : "x"
        return Edit(range: interior, replacement: replacement)
    }
}
