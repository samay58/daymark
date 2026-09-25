import Foundation
@testable import DaymarkCore

/// Scans the lines `range` touches, entering them with the fence state a full-note cache holds
/// at that point, the way the live editor rescans an edited line.
func scanLinesWithCachedFence(_ text: String, in range: NSRange) -> NoteTokens {
    let ns = text as NSString
    let location = min(max(0, range.location), ns.length)
    let lineStart = ns.lineRange(for: NSRange(location: location, length: 0)).location
    let entering = NoteTokenCacheReducer.fenceStates(for: text).last { $0.location <= lineStart }?.fence
    return NoteTokenScanner.scanLines(text, in: range, fence: entering ?? MarkdownFenceScanner())
}
