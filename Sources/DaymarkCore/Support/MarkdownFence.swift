import Foundation

/// Tracks fenced code block state across Markdown lines using CommonMark-style fence
/// matching. A fence opens on a run of at least three backticks or tildes and closes
/// only on a line that is a run of the same fence character, at least as long as the
/// opener, with nothing after it but spaces or tabs. A different or shorter fence marker
/// inside the block is treated as content, so it cannot end the block early.
public struct MarkdownFenceScanner: Sendable {
    private var openCharacter: Character?
    private var openLength = 0

    public init() {}

    public var isInsideFence: Bool { openCharacter != nil }

    /// Feeds the next line, trimmed of at least its leading whitespace, and updates fence state.
    /// Returns true when the line is a fence delimiter (an opener or a matching closer),
    /// which callers skip the same way they skip lines inside a fence.
    public mutating func consume(trimmedLine: String) -> Bool {
        if let openCharacter {
            if Self.isClosingFence(trimmedLine, character: openCharacter, minimumLength: openLength) {
                self.openCharacter = nil
                openLength = 0
                return true
            }
            return false
        }
        if let opener = Self.openingFence(trimmedLine) {
            openCharacter = opener.character
            openLength = opener.length
            return true
        }
        return false
    }

    private static func openingFence(_ trimmed: String) -> (character: Character, length: Int)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        return (first, run)
    }

    // Trailing spaces and tabs are allowed after a closing run, as in CommonMark. Callers that
    // trim only the leading side (the editor's scanner) then agree with callers that trim both.
    private static func isClosingFence(_ trimmed: String, character: Character, minimumLength: Int) -> Bool {
        var run = Substring(trimmed)
        while let last = run.last, last == " " || last == "\t" { run = run.dropLast() }
        guard !run.isEmpty, run.count >= minimumLength else { return false }
        return run.allSatisfy { $0 == character }
    }
}

/// Builds backtick code fences that are guaranteed to wrap their body safely.
public enum MarkdownCodeFence {
    /// Wraps `body` in a backtick fence long enough that no backtick run inside the body
    /// can close it early (CommonMark requires the closing fence to be at least as long as
    /// the opener). A backtick-free body uses a normal three-backtick fence. The optional
    /// info string is attached to the opening fence.
    public static func wrap(_ body: String, info: String = "") -> String {
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: body) + 1))
        return "\(fence)\(info)\n\(body)\n\(fence)"
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
}
