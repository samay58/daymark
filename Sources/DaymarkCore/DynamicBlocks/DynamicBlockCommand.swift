import Foundation

public enum DynamicBlockCommand: String, CaseIterable, Sendable {
    case openLoops = "open-loops"
    case sourceList = "source-list"
    case codexContext = "codex-context"
    case weeklyReview = "weekly-review"
}

public struct DynamicBlockInvocation: Equatable, Sendable {
    public var sourcePath: String
    public var lineNumber: Int
    public var rawText: String
    public var command: DynamicBlockCommand
    public var arguments: [String]
    public var ordinal: Int

    public init(
        sourcePath: String,
        lineNumber: Int,
        rawText: String,
        command: DynamicBlockCommand,
        arguments: [String] = [],
        ordinal: Int
    ) {
        self.sourcePath = sourcePath
        self.lineNumber = lineNumber
        self.rawText = rawText
        self.command = command
        self.arguments = arguments
        self.ordinal = ordinal
    }

    public var commandHash: String {
        String(ContentHasher.hash("\(sourcePath)\n\(ordinal)\n\(rawText)").prefix(12))
    }
}

public struct DynamicBlockSource: Equatable, Sendable {
    public var title: String
    public var relativePath: String
    public var tags: [String]

    public init(title: String, relativePath: String, tags: [String]) {
        self.title = title
        self.relativePath = relativePath
        self.tags = tags
    }
}

public enum DynamicBlockCodexContextKind: String, Equatable, Sendable {
    case taskSpec
    case contextBundle
}

public struct DynamicBlockCodexContextArtifact: Equatable, Sendable {
    public var kind: DynamicBlockCodexContextKind
    public var title: String
    public var relativePath: String
    public var tags: [String]
    public var sourcePaths: [String]
    public var taskPaths: [String]

    public init(
        kind: DynamicBlockCodexContextKind,
        title: String,
        relativePath: String,
        tags: [String],
        sourcePaths: [String] = [],
        taskPaths: [String] = []
    ) {
        self.kind = kind
        self.title = title
        self.relativePath = relativePath
        self.tags = tags
        self.sourcePaths = sourcePaths
        self.taskPaths = taskPaths
    }
}

public enum DynamicBlockError: LocalizedError, Equatable {
    case unsupportedCommand(name: String, line: Int)
    case unsupportedRenderer(DynamicBlockCommand)
    case unsupportedArgument(command: DynamicBlockCommand, argument: String)
    case missingGeneratedRegionEnd(line: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let name, let line):
            return "unsupported dynamic block command on line \(line): \(name)"
        case .unsupportedRenderer(let command):
            return "dynamic block command is not implemented yet: \(command.rawValue)"
        case .unsupportedArgument(let command, let argument):
            return "unsupported argument for \(command.rawValue): \(argument)"
        case .missingGeneratedRegionEnd(let line):
            return "generated dynamic block region starting on line \(line) has no end marker"
        }
    }
}

public struct DynamicBlockParser: Sendable {
    public init() {}

    public func parse(markdown: String, sourcePath: String) throws -> [DynamicBlockInvocation] {
        let lines = Self.normalized(markdown).components(separatedBy: "\n")
        var invocations: [DynamicBlockInvocation] = []
        var fence = MarkdownFenceScanner()

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence.consume(trimmedLine: trimmed) { continue }
            if fence.isInsideFence { continue }

            let parts = trimmed.split { $0 == " " || $0 == "\t" }.map(String.init)
            guard parts.first == "/daymark" else { continue }
            guard parts.count >= 2 else { continue }
            let commandName = parts[1]
            guard let command = DynamicBlockCommand(rawValue: commandName) else {
                throw DynamicBlockError.unsupportedCommand(name: commandName, line: index + 1)
            }
            invocations.append(DynamicBlockInvocation(
                sourcePath: sourcePath,
                lineNumber: index + 1,
                rawText: trimmed,
                command: command,
                arguments: Array(parts.dropFirst(2)),
                ordinal: invocations.count + 1
            ))
        }

        return invocations
    }

    static func normalized(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

public struct DynamicBlockRenderer: Sendable {
    public init() {}

    public func render(
        invocation: DynamicBlockInvocation,
        tasks: [TaskItem],
        sources: [DynamicBlockSource] = [],
        codexContexts: [DynamicBlockCodexContextArtifact] = [],
        referenceDate: Date,
        calendar: Calendar = .current
    ) throws -> String {
        switch invocation.command {
        case .openLoops:
            return try renderOpenLoops(
                invocation: invocation,
                tasks: tasks,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .sourceList:
            return try renderSourceList(invocation: invocation, sources: sources)
        case .codexContext:
            return try renderCodexContext(invocation: invocation, contexts: codexContexts)
        case .weeklyReview:
            return try renderWeeklyReview(
                invocation: invocation,
                tasks: tasks,
                sources: sources,
                codexContexts: codexContexts,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    private func renderOpenLoops(
        invocation: DynamicBlockInvocation,
        tasks: [TaskItem],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> String {
        let tagFilters = try invocation.arguments.map { argument in
            guard argument.hasPrefix("#") else {
                throw DynamicBlockError.unsupportedArgument(command: invocation.command, argument: argument)
            }
            return argument
        }
        let filteredTasks = tagFilters.isEmpty
            ? tasks
            : tasks.filter { task in tagFilters.allSatisfy { task.tags.contains($0) } }
        let groups = OpenLoops.grouped(tasks: filteredTasks, on: referenceDate, calendar: calendar)
        let total = groups.reduce(0) { $0 + $1.tasks.count }

        var lines: [String] = ["### Open Loops", ""]
        guard total > 0 else {
            if let tag = tagFilters.first {
                lines.append("No open loops for \(tag).")
            } else {
                lines.append("No open loops.")
            }
            return lines.joined(separator: "\n") + "\n"
        }

        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 { lines.append("") }
            lines.append("#### \(group.bucket.title)")
            for task in group.tasks {
                lines.append("- [ ] \(task.title)  (\(task.notePath):\(task.lineNumber))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func renderSourceList(
        invocation: DynamicBlockInvocation,
        sources: [DynamicBlockSource]
    ) throws -> String {
        guard let tag = invocation.arguments.first else {
            return "### Source List\n\nAdd a tag argument, for example `#project/daymark`.\n"
        }
        guard tag.hasPrefix("#"), invocation.arguments.count == 1 else {
            let argument = invocation.arguments.first(where: { !$0.hasPrefix("#") })
                ?? invocation.arguments.dropFirst().first
                ?? tag
            throw DynamicBlockError.unsupportedArgument(command: invocation.command, argument: argument)
        }

        let matches = sources
            .filter { $0.tags.contains(tag) }
            .sorted { lhs, rhs in
                if lhs.relativePath == rhs.relativePath { return lhs.title < rhs.title }
                return lhs.relativePath < rhs.relativePath
            }

        var lines = ["### Source List: \(tag)", ""]
        guard !matches.isEmpty else {
            lines.append("No sources found for \(tag).")
            return lines.joined(separator: "\n") + "\n"
        }

        for source in matches {
            lines.append("- \(source.title) (`\(source.relativePath)`)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderCodexContext(
        invocation: DynamicBlockInvocation,
        contexts: [DynamicBlockCodexContextArtifact]
    ) throws -> String {
        guard let tag = invocation.arguments.first else {
            return "### Codex Context\n\nAdd a tag argument, for example `#project/daymark`.\n"
        }
        guard tag.hasPrefix("#"), invocation.arguments.count == 1 else {
            let argument = invocation.arguments.first(where: { !$0.hasPrefix("#") })
                ?? invocation.arguments.dropFirst().first
                ?? tag
            throw DynamicBlockError.unsupportedArgument(command: invocation.command, argument: argument)
        }

        let matches = contexts
            .filter { $0.tags.contains(tag) }
            .sorted { lhs, rhs in
                if lhs.kind == rhs.kind {
                    return lhs.relativePath < rhs.relativePath
                }
                return lhs.kind == .taskSpec
            }
        let taskSpecs = matches.filter { $0.kind == .taskSpec }
        let bundles = matches.filter { $0.kind == .contextBundle }

        var lines = ["### Codex Context: \(tag)", ""]
        guard !matches.isEmpty else {
            lines.append("No Codex context found for \(tag).")
            return lines.joined(separator: "\n") + "\n"
        }

        if !taskSpecs.isEmpty {
            lines.append("#### Task Specs")
            for artifact in taskSpecs {
                lines.append("- \(artifact.title) (`\(artifact.relativePath)`)\(referenceSuffix(for: artifact))")
            }
        }

        if !bundles.isEmpty {
            if !taskSpecs.isEmpty { lines.append("") }
            lines.append("#### Context Bundles")
            for artifact in bundles {
                lines.append("- \(artifact.title) (`\(artifact.relativePath)`)\(referenceSuffix(for: artifact))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func referenceSuffix(for artifact: DynamicBlockCodexContextArtifact) -> String {
        var parts: [String] = []
        if let taskPath = artifact.taskPaths.first {
            parts.append("task: `\(taskPath)`")
        }
        if let sourcePath = artifact.sourcePaths.first {
            parts.append("source: `\(sourcePath)`")
        }
        return parts.isEmpty ? "" : " " + parts.joined(separator: "; ")
    }

    private func renderWeeklyReview(
        invocation: DynamicBlockInvocation,
        tasks: [TaskItem],
        sources: [DynamicBlockSource],
        codexContexts: [DynamicBlockCodexContextArtifact],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> String {
        if let argument = invocation.arguments.first {
            throw DynamicBlockError.unsupportedArgument(command: invocation.command, argument: argument)
        }

        let week = WeekWindow(containing: referenceDate, calendar: calendar)
        let completedThisWeek = tasks
            .filter { $0.status == .completed && week.containsDailyNotePath($0.notePath, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.notePath == rhs.notePath { return lhs.lineNumber < rhs.lineNumber }
                return lhs.notePath < rhs.notePath
            }
        let recentContexts = codexContexts
            .filter { week.containsArtifactPath($0.relativePath, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.kind == rhs.kind { return lhs.relativePath < rhs.relativePath }
                return lhs.kind == .taskSpec
            }
        let sourceTitles = Dictionary(uniqueKeysWithValues: sources.map { ($0.relativePath, $0.title) })
        let sourcePaths = Array(Set(recentContexts.flatMap(\.sourcePaths))).sorted()

        var lines = ["### Weekly Review", ""]
        lines.append("#### Still Open")
        let groups = OpenLoops.grouped(tasks: tasks, on: referenceDate, calendar: calendar)
        if groups.isEmpty {
            lines.append("No open loops.")
        } else {
            for (groupIndex, group) in groups.enumerated() {
                if groupIndex > 0 { lines.append("") }
                lines.append("##### \(group.bucket.title)")
                for task in group.tasks {
                    lines.append("- [ ] \(task.title)  (\(task.notePath):\(task.lineNumber))")
                }
            }
        }

        lines.append("")
        lines.append("#### Completed This Week")
        if completedThisWeek.isEmpty {
            lines.append("No completed tasks found for this week.")
        } else {
            for task in completedThisWeek {
                lines.append("- [x] \(task.title)  (\(task.notePath):\(task.lineNumber))")
            }
        }

        lines.append("")
        lines.append("#### Codex Handoffs")
        if recentContexts.isEmpty {
            lines.append("No Codex handoffs found for this week.")
        } else {
            for artifact in recentContexts {
                let label = artifact.kind == .taskSpec ? "Task" : "Bundle"
                lines.append("- \(label): \(artifact.title) (`\(artifact.relativePath)`)\(referenceSuffix(for: artifact))")
            }
        }

        lines.append("")
        lines.append("#### Sources To Revisit")
        if sourcePaths.isEmpty {
            lines.append("No source notes found from this week's handoffs.")
        } else {
            for path in sourcePaths {
                lines.append("- \(sourceTitles[path] ?? path) (`\(path)`)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

private struct WeekWindow {
    var start: Date
    var end: Date

    init(containing date: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        self.start = interval?.start ?? calendar.startOfDay(for: date)
        self.end = interval?.end ?? calendar.date(byAdding: .day, value: 7, to: self.start) ?? date
    }

    func containsDailyNotePath(_ path: String, calendar: Calendar) -> Bool {
        guard let date = Self.date(fromDailyNotePath: path, calendar: calendar) else { return false }
        return contains(date)
    }

    func containsArtifactPath(_ path: String, calendar: Calendar) -> Bool {
        guard let date = Self.date(fromArtifactPath: path, calendar: calendar) else { return false }
        return contains(date)
    }

    private func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    private static func date(fromDailyNotePath path: String, calendar: Calendar) -> Date? {
        let filename = (path as NSString).lastPathComponent
        guard filename.hasSuffix(".md"), filename.count >= 13 else { return nil }
        return date(fromISO: String(filename.prefix(10)), calendar: calendar)
    }

    private static func date(fromArtifactPath path: String, calendar: Calendar) -> Date? {
        let filename = (path as NSString).lastPathComponent
        guard filename.count >= 10 else { return nil }
        return date(fromISO: String(filename.prefix(10)), calendar: calendar)
    }

    private static func date(fromISO iso: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: iso)
    }
}

public enum DynamicBlockPatchOperation: Equatable, Sendable {
    case insert
    case replacement
}

public struct DynamicBlockPatch: Equatable, Sendable {
    public var targetFilePath: String
    public var commandLine: Int
    public var rawCommand: String
    public var command: DynamicBlockCommand
    public var commandHash: String
    public var operation: DynamicBlockPatchOperation
    public var generatedMarkdown: String
    public var replacementMarkdown: String

    let startLineIndex: Int
    let endLineIndex: Int
}

public struct DynamicBlockPatchPlan: Equatable, Sendable {
    public var targetFilePath: String
    public var patches: [DynamicBlockPatch]

    public func apply(to markdown: String) throws -> String {
        // Patch on LF internally, but re-emit with the file's existing dominant line
        // ending so untouched lines outside the generated region are never silently
        // rewritten (a CRLF note stays CRLF; an LF note stays LF).
        let lineEnding = markdown.contains("\r\n") ? "\r\n" : "\n"
        var lines = DynamicBlockParser.normalized(markdown).components(separatedBy: "\n")
        for patch in patches.sorted(by: { $0.startLineIndex > $1.startLineIndex }) {
            let replacementLines = patch.replacementMarkdown.components(separatedBy: "\n")
            switch patch.operation {
            case .insert:
                lines.insert(contentsOf: replacementLines, at: patch.startLineIndex)
            case .replacement:
                lines.replaceSubrange(patch.startLineIndex...patch.endLineIndex, with: replacementLines)
            }
        }
        return lines.joined(separator: lineEnding)
    }
}

public struct DynamicBlockPatchPlanner: Sendable {
    private let parser: DynamicBlockParser
    private let renderer: DynamicBlockRenderer

    public init(parser: DynamicBlockParser = DynamicBlockParser(), renderer: DynamicBlockRenderer = DynamicBlockRenderer()) {
        self.parser = parser
        self.renderer = renderer
    }

    public func plan(
        markdown: String,
        sourcePath: String,
        tasks: [TaskItem],
        sources: [DynamicBlockSource] = [],
        codexContexts: [DynamicBlockCodexContextArtifact] = [],
        referenceDate: Date,
        calendar: Calendar = .current
    ) throws -> DynamicBlockPatchPlan {
        let normalized = DynamicBlockParser.normalized(markdown)
        let lines = normalized.components(separatedBy: "\n")
        let invocations = try parser.parse(markdown: normalized, sourcePath: sourcePath)
        var patches: [DynamicBlockPatch] = []

        for invocation in invocations {
            let generated = try renderer.render(
                invocation: invocation,
                tasks: tasks,
                sources: sources,
                codexContexts: codexContexts,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let region = Self.generatedRegion(hash: invocation.commandHash, markdown: generated)
            let commandIndex = invocation.lineNumber - 1
            let regionStart = commandIndex + 1

            if regionStart < lines.count, let beginHash = GeneratedRegionMarker.beginHash(in: lines[regionStart]) {
                // Bound the region by the existing begin marker's hash, not the new
                // invocation hash: editing the command text changes the invocation hash,
                // and the in-place region must still be found and replaced.
                guard let regionEnd = GeneratedRegionMarker.endIndex(afterBegin: regionStart, hash: beginHash, in: lines) else {
                    throw DynamicBlockError.missingGeneratedRegionEnd(line: regionStart + 1)
                }
                patches.append(DynamicBlockPatch(
                    targetFilePath: sourcePath,
                    commandLine: invocation.lineNumber,
                    rawCommand: invocation.rawText,
                    command: invocation.command,
                    commandHash: invocation.commandHash,
                    operation: .replacement,
                    generatedMarkdown: generated,
                    replacementMarkdown: region,
                    startLineIndex: regionStart,
                    endLineIndex: regionEnd
                ))
            } else {
                patches.append(DynamicBlockPatch(
                    targetFilePath: sourcePath,
                    commandLine: invocation.lineNumber,
                    rawCommand: invocation.rawText,
                    command: invocation.command,
                    commandHash: invocation.commandHash,
                    operation: .insert,
                    generatedMarkdown: generated,
                    replacementMarkdown: region,
                    startLineIndex: regionStart,
                    endLineIndex: regionStart
                ))
            }
        }

        return DynamicBlockPatchPlan(targetFilePath: sourcePath, patches: patches)
    }

    static func generatedRegion(hash: String, markdown: String) -> String {
        let body = markdown.trimmingCharacters(in: .newlines)
        return """
        \(GeneratedRegionMarker.begin(hash: hash))
        \(body)
        \(GeneratedRegionMarker.end(hash: hash))
        """
    }
}

/// Parses and builds the HTML-comment markers that wrap a generated dynamic-block region
/// (ADR-009). Pairing is hash-aware so an unrelated or shorter-hash end marker cannot be
/// mistaken for a region's close.
enum GeneratedRegionMarker {
    static let beginPrefix = "<!-- daymark:block-begin "
    static let endPrefix = "<!-- daymark:block-end "

    static func begin(hash: String) -> String { "\(beginPrefix)\(hash) -->" }
    static func end(hash: String) -> String { "\(endPrefix)\(hash) -->" }

    static func beginHash(in line: String) -> String? { hash(in: line, prefix: beginPrefix) }
    static func endHash(in line: String) -> String? { hash(in: line, prefix: endPrefix) }

    /// The first end marker after `beginIndex` carrying `hash`, or nil if none exists.
    static func endIndex(afterBegin beginIndex: Int, hash: String, in lines: [String]) -> Int? {
        guard beginIndex + 1 <= lines.count else { return nil }
        for index in (beginIndex + 1)..<lines.count where endHash(in: lines[index]) == hash {
            return index
        }
        return nil
    }

    private static func hash(in line: String, prefix: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let remainder = trimmed.dropFirst(prefix.count)
        let token = remainder.split(whereSeparator: { $0 == " " }).first.map(String.init)
        return (token?.isEmpty == false) ? token : nil
    }
}

public enum DynamicBlockRegion {
    /// Removes only COMPLETE generated regions: a begin marker that has a matching end
    /// marker with the same hash. A begin marker with no matching end (a malformed or
    /// hand-edited region) is preserved verbatim along with everything after it, so a
    /// stray marker can never silently drop following real tasks from the projection.
    public static func removingGeneratedRegions(from markdown: String) -> String {
        let lines = DynamicBlockParser.normalized(markdown).components(separatedBy: "\n")
        var kept: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if let beginHash = GeneratedRegionMarker.beginHash(in: line),
               let endIndex = GeneratedRegionMarker.endIndex(afterBegin: index, hash: beginHash, in: lines) {
                index = endIndex + 1
                continue
            }
            kept.append(line)
            index += 1
        }

        return kept.joined(separator: "\n")
    }
}
