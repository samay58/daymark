import Foundation

public struct TaskParser {
    public init() {}

    /// Parses Markdown checkbox lines into tasks, preserving source metadata. The scan is
    /// conservative and Markdown-readable: only `- [ ]`, `- [x]`, and `- [X]` count, lines
    /// inside fenced code blocks are ignored, and the title keeps the line's text verbatim.
    /// `notePath` stamps each task with the workspace-relative path of its source note.
    public func parse(markdown: String, notePath: String = "") -> [TaskItem] {
        let lines = Self.normalizingNewlines(markdown).components(separatedBy: "\n")
        var tasks: [TaskItem] = []
        var inFence = false
        var section: String?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            if let heading = Self.headingText(trimmed) {
                section = heading
                continue
            }

            guard let parsed = Self.checkbox(of: trimmed) else { continue }
            let body = parsed.body
            tasks.append(TaskItem(
                title: body,
                status: parsed.status,
                tags: Self.tokens(in: body, prefixedBy: "#"),
                mentions: Self.tokens(in: body, prefixedBy: "@"),
                due: Self.due(in: body),
                notePath: notePath,
                lineNumber: index + 1,
                originalLine: line,
                sectionHeading: section
            ))
        }
        return tasks
    }

    // MARK: - Line classification

    /// The checkbox status and body for a task line, or nil if the line is not a task.
    private static func checkbox(of trimmed: String) -> (status: TaskItem.Status, body: String)? {
        guard trimmed.hasPrefix("- ["), trimmed.count >= 5 else { return nil }
        let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let closeIndex = trimmed.index(after: markerIndex)
        guard trimmed[closeIndex] == "]" else { return nil }

        let status: TaskItem.Status
        switch trimmed[markerIndex] {
        case " ": status = .open
        case "x", "X": status = .completed
        default: return nil
        }

        let body = String(trimmed[trimmed.index(after: closeIndex)...]).trimmingCharacters(in: .whitespaces)
        return (status, body)
    }

    /// The text of an ATX heading (`#`..`######` followed by a space), or nil. Requiring the
    /// space keeps bare `#tag` lines from being read as headings.
    private static func headingText(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    // MARK: - Metadata extraction

    private static func tokens(in body: String, prefixedBy prefix: Character) -> [String] {
        words(in: body)
            .filter { $0.first == prefix && $0.count > 1 }
            .map(String.init)
    }

    private static func due(in body: String) -> TaskItem.Due? {
        for word in words(in: body) where word.hasPrefix("due:") {
            let value = String(word.dropFirst("due:".count))
            if let due = TaskItem.Due(token: value) { return due }
        }
        return nil
    }

    private static func words(in body: String) -> [Substring] {
        body.split(omittingEmptySubsequences: true) { (character: Character) in
            character == " " || character == "\t"
        }
    }

    private static func normalizingNewlines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
