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
