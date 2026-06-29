import Foundation

/// Pure Markdown editing primitive for capture: append a block under a named heading
/// without ever duplicating that heading or disturbing other sections. Operates on
/// strings only, so it is the same logic whether the buffer is in memory or on disk.
public enum MarkdownSection {
    /// Appends `entry` to the end of the section introduced by `heading`. When the heading
    /// is absent, the heading and entry are added to the end of the document. The heading is
    /// never duplicated, and content in other sections is preserved.
    public static func appendingEntry(_ entry: String, under heading: String, to document: String) -> String {
        let entryLines = entry.components(separatedBy: "\n")
        let targetHeading = heading.trimmingCharacters(in: .whitespaces)
        let targetLevel = headingLevel(of: targetHeading) ?? 0

        var lines = document.components(separatedBy: "\n")
        let headingIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == targetHeading }

        if let h = headingIndex {
            // The section runs until the next heading of equal or higher level, or the end.
            var boundary = lines.count
            var i = h + 1
            while i < lines.count {
                if let level = headingLevel(of: lines[i]), level <= targetLevel {
                    boundary = i
                    break
                }
                i += 1
            }

            let head = Array(lines[0...h])
            let tail = Array(lines[boundary...])
            let inner = trimmingBlankEnds(Array(lines[(h + 1)..<boundary]))

            var mid: [String] = [""]
            if !inner.isEmpty {
                mid += inner
                mid += [""]
            }
            mid += entryLines
            if !tail.isEmpty {
                mid += [""]
            }

            lines = head + mid + tail
        } else {
            let core = trimmingBlankEnds(lines)
            var parts = core
            if !core.isEmpty {
                parts += [""]
            }
            parts += [targetHeading, ""]
            parts += entryLines
            lines = parts
        }

        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    // MARK: - Helpers

    /// The ATX heading level of a line (`## Foo` is 2), or nil when the line is not a heading.
    private static func headingLevel(of line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var count = 0
        for character in trimmed {
            if character == "#" { count += 1 } else { break }
        }
        let rest = trimmed.dropFirst(count)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        return count
    }

    private static func trimmingBlankEnds(_ lines: [String]) -> [String] {
        var result = lines
        while let first = result.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeFirst()
        }
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result
    }
}
