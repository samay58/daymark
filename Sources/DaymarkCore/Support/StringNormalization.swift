import Foundation

public extension String {
    /// The string with CRLF and lone CR line endings converted to LF. Markdown enters the
    /// app from disk, paste, and external editors with mixed endings; normalizing in one
    /// place keeps parsing, hashing, and diffing consistent across the codebase.
    var normalizedNewlines: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

/// Line ranges in Markdown as written, for mapping a line index from normalized text back onto
/// the original. NSString line enumeration cannot do this: it also breaks on U+2028, U+2029,
/// and U+0085, which `normalizedNewlines` leaves inside a line.
public enum MarkdownLineRanges {
    /// UTF-16 range of each line of `markdown`, not counting its terminator. Index `i` is line
    /// `i` of `markdown.normalizedNewlines.components(separatedBy: "\n")`, since this splits on
    /// exactly LF, CRLF, and lone CR.
    public static func utf16Ranges(in markdown: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var lineStart = 0
        var offset = 0
        var previousWasCR = false
        for unit in markdown.utf16 {
            switch unit {
            case 0x0D:
                ranges.append(NSRange(location: lineStart, length: offset - lineStart))
                lineStart = offset + 1
                previousWasCR = true
            case 0x0A:
                // The CR of a CRLF pair already ended the line.
                if !previousWasCR {
                    ranges.append(NSRange(location: lineStart, length: offset - lineStart))
                }
                lineStart = offset + 1
                previousWasCR = false
            default:
                previousWasCR = false
            }
            offset += 1
        }
        ranges.append(NSRange(location: lineStart, length: offset - lineStart))
        return ranges
    }
}
