import Foundation
import DaymarkCore

public struct MarkdownParser {
    public init() {}

    /// Splits Markdown into one block per source line. Block identity is line-positional;
    /// later milestones can introduce semantic block grouping without changing the store.
    public func blocks(from markdown: String) -> [Block] {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                Block(id: "line_\(index + 1)", markdown: String(line), lineStart: index + 1, lineEnd: index + 1)
            }
    }

    /// The note title: the first ATX heading text if present, otherwise the first
    /// non-empty line, otherwise nil. Used for the search index and note list.
    public func title(from markdown: String) -> String? {
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let stripped = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return stripped.isEmpty ? nil : stripped
            }
            return line
        }
        return nil
    }
}
