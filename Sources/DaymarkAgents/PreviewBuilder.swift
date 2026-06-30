import Foundation
import DaymarkCore

public struct PreviewBuilder {
    public enum Error: Swift.Error, Equatable {
        case emptySource
    }

    public init() {}

    public func codexTaskPreview(
        source: SourceSelection,
        date: Date,
        existingRelativePaths: Set<String>
    ) throws -> CodexTaskDraft {
        let excerpt = source.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !excerpt.isEmpty else { throw Error.emptySource }

        let title = title(from: excerpt)
        let preferredPath = CodexTaskDraft.suggestedRelativePath(title: title, date: date)
        let suggestedPath = CodexTaskDraft.collisionSafeRelativePath(
            preferredPath: preferredPath,
            existingRelativePaths: existingRelativePaths
        )

        return CodexTaskDraft(
            title: title,
            goal: goal(from: excerpt),
            sourcePath: source.sourcePath,
            sourceLine: source.startLine,
            sourceEndLine: source.endLine,
            sourceBlock: source.heading,
            sourceExcerpt: excerpt,
            constraints: [
                "Do not modify the source note",
                "Do not run Codex automatically"
            ],
            suggestedFilePath: suggestedPath,
            acceptanceCriteria: [
                "Source note remains unchanged",
                "Source excerpt is preserved in the task file",
                "Task file is readable Markdown",
                "Behavior is verified with tests or a manual check"
            ]
        )
    }

    private func title(from excerpt: String) -> String {
        let first = excerpt
            .components(separatedBy: .newlines)
            .map { stripMarkdownPrefix($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Codex task"
        let words = first
            .split(separator: " ")
            .prefix(8)
            .joined(separator: " ")
        let trimmed = words.trimmingCharacters(in: CharacterSet(charactersIn: ".:,;!?- "))
        return trimmed.isEmpty ? "Codex task" : trimmed
    }

    private func goal(from excerpt: String) -> String {
        let lines = excerpt
            .components(separatedBy: .newlines)
            .map { stripMarkdownPrefix($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        let paragraph = lines
            .split(whereSeparator: { $0.isEmpty })
            .first?
            .joined(separator: " ") ?? ""

        let trimmed = String(paragraph.prefix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title(from: excerpt) : trimmed
    }

    private func stripMarkdownPrefix(_ line: String) -> String {
        var output = line
        output = MarkdownHeading.strippingMarker(output)
        output = output.replacingOccurrences(
            of: #"^\s{0,3}[-*+]\s+\[[ xX]\]\s+"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"^\s{0,3}[-*+]\s+"#,
            with: "",
            options: .regularExpression
        )
        return output
    }
}
