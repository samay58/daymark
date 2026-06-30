import Foundation

/// Shared ATX heading recognition: up to three leading spaces, one to six `#`, then required
/// whitespace (CommonMark). Kept in one place so heading detection and prefix stripping cannot
/// drift on the allowed indentation. List-marker patterns are deliberately not here; they
/// differ in body and purpose across call sites.
public enum MarkdownHeading {
    public static let atxPattern = #"^\s{0,3}#{1,6}\s+"#

    public static func isHeading(_ line: String) -> Bool {
        line.range(of: atxPattern, options: .regularExpression) != nil
    }

    /// The line with its ATX heading marker removed; a no-op for non-headings.
    public static func strippingMarker(_ line: String) -> String {
        line.replacingOccurrences(of: atxPattern, with: "", options: .regularExpression)
    }
}
