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
        var inFence = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

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
        case .sourceList, .codexContext, .weeklyReview:
            throw DynamicBlockError.unsupportedRenderer(invocation.command)
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
        return lines.joined(separator: "\n")
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
                referenceDate: referenceDate,
                calendar: calendar
            )
            let region = Self.generatedRegion(hash: invocation.commandHash, markdown: generated)
            let commandIndex = invocation.lineNumber - 1
            let regionStart = commandIndex + 1

            if regionStart < lines.count, Self.isBeginMarker(lines[regionStart]) {
                guard let regionEnd = Self.endMarkerIndex(startingAt: regionStart, in: lines) else {
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
        <!-- daymark:block-begin \(hash) -->
        \(body)
        <!-- daymark:block-end \(hash) -->
        """
    }

    private static func isBeginMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("<!-- daymark:block-begin ")
    }

    private static func isEndMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("<!-- daymark:block-end ")
    }

    private static func endMarkerIndex(startingAt start: Int, in lines: [String]) -> Int? {
        guard start < lines.count else { return nil }
        for index in start..<lines.count where isEndMarker(lines[index]) {
            return index
        }
        return nil
    }
}

public enum DynamicBlockRegion {
    public static func removingGeneratedRegions(from markdown: String) -> String {
        let lines = DynamicBlockParser.normalized(markdown).components(separatedBy: "\n")
        var kept: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<!-- daymark:block-begin ") {
                skipping = true
                continue
            }
            if trimmed.hasPrefix("<!-- daymark:block-end ") {
                skipping = false
                continue
            }
            if !skipping {
                kept.append(line)
            }
        }

        return kept.joined(separator: "\n")
    }
}
