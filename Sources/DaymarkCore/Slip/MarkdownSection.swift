import Foundation

/// Pure Markdown editing primitive for capture: append a block under a named heading
/// without ever duplicating that heading or disturbing other sections. Operates on
/// strings only, so it is the same logic whether the buffer is in memory or on disk.
public enum MarkdownSection {
    /// Appends `entry` to the end of the section introduced by `heading`. When the heading
    /// is absent, the heading and entry are added to the end of the document. The heading is
    /// never duplicated, and content in other sections is preserved.
    public static func appendingEntry(_ entry: String, under heading: String, to document: String) -> String {
        // Normalize to LF so CRLF or lone-CR documents still match headings (a trailing "\r"
        // would otherwise defeat the heading comparison and append a duplicate heading).
        let entryLines = normalizingNewlines(entry).components(separatedBy: "\n")
        let targetHeading = heading.trimmingCharacters(in: .whitespaces)
        let targetLevel = headingLevel(of: targetHeading) ?? 0

        var lines = normalizingNewlines(document).components(separatedBy: "\n")
        // Heading levels computed once, ignoring anything inside fenced code blocks so a
        // `##` line in a code sample is never mistaken for a section heading.
        let levels = headingLevels(of: lines)
        let headingIndex = lines.indices.first { index in
            levels[index] != nil && lines[index].trimmingCharacters(in: .whitespaces) == targetHeading
        }

        if let h = headingIndex {
            // The section runs until the next heading of equal or higher level, or the end.
            var boundary = lines.count
            var i = h + 1
            while i < lines.count {
                if let level = levels[i], level <= targetLevel {
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

    private static func normalizingNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

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

    /// The heading level of each line, counting only ATX headings outside fenced code
    /// blocks. Lines inside ``` or ~~~ fences, and the fence delimiters themselves, are nil.
    private static func headingLevels(of lines: [String]) -> [Int?] {
        var levels: [Int?] = []
        levels.reserveCapacity(lines.count)
        var inFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                levels.append(nil)
                inFence.toggle()
                continue
            }
            levels.append(inFence ? nil : headingLevel(of: line))
        }
        return levels
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
