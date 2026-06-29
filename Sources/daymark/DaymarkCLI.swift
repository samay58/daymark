import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import DaymarkCore
import DaymarkStore
import DaymarkIndexer
import DaymarkAgents

@main
struct DaymarkCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var command = "help"
        var options: [String] = []
        var root = WorkspaceRoot.resolve()

        do {
            let parsed = try parseCommandAndRootOptions(arguments)
            command = parsed.command
            options = parsed.options
            root = parsed.root

            switch command {
            case "doctor":
                runDoctor(root: root)
            case "init":
                try runInit(root: root)
            case "index":
                try await runIndex(root: root)
            case "rebuild":
                try await runRebuild(root: root)
            case "capture":
                try runCapture(arguments: options, root: root)
            case "rollover":
                try await runRollover(arguments: options, root: root)
            case "end-of-day":
                try await runEndOfDay(arguments: options, root: root)
            case "open-loops":
                try await runOpenLoops(root: root)
            case "codex-task":
                try runCodexTask(arguments: options, root: root)
            case "context-bundle":
                try runContextBundle(arguments: options, root: root)
            case "search":
                try await runSearch(arguments: options, root: root)
            case "today":
                try runToday(root: root)
            case "help", "--help", "-h":
                printUsage()
            default:
                throw CommandError.unknownCommand(command)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write(Data("daymark \(command): \(message)\n".utf8))
            if let usage = (error as? CommandError)?.usage { printUsage(to: .standardError, message: usage) }
            exit(1)
        }
        // Swift's async `@main` keeps the process alive after the task returns; exit explicitly.
        exit(0)
    }

    // MARK: - Commands

    /// Read-only health check. Never creates directories or the database.
    private static func runDoctor(root: WorkspaceRoot) {
        let health = WorkspaceHealth.inspect(root: root)

        print("Daymark doctor")
        print("Workspace: \(health.rootRawPath) -> \(health.rootExpandedPath)")
        for directory in health.directories {
            print("  [\(directory.exists ? "x" : " ")] \(directory.relativePath)")
        }
        print("Today's note: \(health.todayNoteExists ? "present" : "missing") (\(health.todayRelativePath))")
        print("Daily Markdown files: \(health.dailyMarkdownCount)")
        print("Index database: \(health.databaseExists ? "present" : "absent") (\(health.databasePath))")
        print("Declared migrations: \(health.declaredMigrations.joined(separator: ", "))")

        if !health.isBootstrapped || !health.todayNoteExists {
            print("Run `daymark init` to create the workspace, then `daymark index`.")
        }
    }

    /// Creates the documented workspace directories and today's note. Additive only.
    private static func runInit(root: WorkspaceRoot) throws {
        let report = try WorkspaceBootstrapper().bootstrap(root: root)
        if report.createdDirectories.isEmpty {
            print("Workspace already present at \(root.expandedPath)")
        } else {
            print("Created \(report.createdDirectories.count) director\(report.createdDirectories.count == 1 ? "y" : "ies") under \(root.expandedPath)")
        }
        let outcome = try DailyNoteStore(root: root).ensureTodayNote()
        print("Today's note: \(outcome.created ? "created" : "already present") (\(outcome.url.path))")
    }

    /// Ensures today's note exists, then projects it into the index database.
    private static func runIndex(root: WorkspaceRoot) async throws {
        try WorkspaceBootstrapper().bootstrap(root: root)
        let store = DailyNoteStore(root: root)
        let outcome = try store.ensureTodayNote()

        let database = Database(configuration: DatabaseConfiguration(path: databaseURL(for: root).path))
        try await database.open()
        _ = try await database.migrate()
        try await WorkspaceIndexer(root: root, database: database).indexToday()
        let notes = try await database.noteCount()
        let blocks = try await database.blockCount()
        await database.close()

        print("Indexed today's note (\(outcome.created ? "created" : "existing")): \(notes) notes, \(blocks) blocks")
    }

    /// Rebuilds the index from every daily Markdown file, proving the database is a
    /// projection of the files on disk.
    private static func runRebuild(root: WorkspaceRoot) async throws {
        let database = Database(configuration: DatabaseConfiguration(path: databaseURL(for: root).path))
        try await database.open()
        _ = try await database.migrate()
        let indexed = try await WorkspaceIndexer(root: root, database: database).rebuild()
        let notes = try await database.noteCount()
        let blocks = try await database.blockCount()
        await database.close()

        print("Rebuilt from \(indexed) Markdown file\(indexed == 1 ? "" : "s"): \(notes) notes, \(blocks) blocks")
    }

    /// Captures text into the workspace as readable Markdown. By default the capture is
    /// appended to this month's Slip file; `--today` appends it under today's `## Capture`
    /// section, and `--task` writes it as an open Markdown task line. Text comes from the
    /// arguments, or from stdin when no text is given. No database work runs on this path.
    private static func runCapture(arguments: [String], root: WorkspaceRoot) throws {
        let parsed = try parseCaptureArguments(arguments)
        let text = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CommandError.missingCaptureText }

        try WorkspaceBootstrapper().bootstrap(root: root)

        switch parsed.target {
        case .today:
            let url = try DailyNoteStore(root: root).appendCapture(text)
            print("Appended to today's note (\(url.path))")
        case .task:
            let url = try DailyNoteStore(root: root).appendTask(text)
            print("Appended task to today's note (\(url.path))")
        case .slip:
            let url = try SlipStore(root: root).save(text)
            print("Saved to slip (\(url.path))")
        }
    }

    private enum CaptureTarget {
        case slip
        case today
        case task
    }

    private struct ParsedCaptureArguments {
        let target: CaptureTarget
        let text: String
    }

    private static func parseCaptureArguments(_ arguments: [String]) throws -> ParsedCaptureArguments {
        var target: CaptureTarget = .slip
        var terms: [String] = []
        var parsingText = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if parsingText {
                terms.append(argument)
                index += 1
                continue
            }

            if argument == "--" {
                parsingText = true
                index += 1
                continue
            }

            switch argument {
            case "--today":
                guard target == .slip else {
                    throw CommandError.captureOptionsConflict(["--today", "--task"])
                }
                target = .today
            case "--task":
                guard target == .slip else {
                    throw CommandError.captureOptionsConflict(["--task", "--today"])
                }
                target = .task
            case let flag where flag.hasPrefix("--"):
                throw CommandError.unknownCaptureFlag(flag)
            default:
                terms.append(argument)
            }

            index += 1
        }

        let text: String
        if terms.isEmpty {
            if let stdin = standardInputText {
                text = stdin
            } else {
                text = ""
            }
        } else {
            text = terms.joined(separator: " ")
        }

        return ParsedCaptureArguments(target: target, text: text)
    }

    private struct ParsedRolloverArguments {
        var date: Date
        var apply: Bool
    }

    /// Rolls open tasks from prior daily notes into Today's Brief. Dry-run by default; pass
    /// `--apply` to write Today's Markdown and record rollover rows.
    private static func runRollover(arguments: [String], root: WorkspaceRoot) async throws {
        let parsed = try parseRolloverArguments(arguments)
        let database = Database(configuration: DatabaseConfiguration(path: databaseURL(for: root).path))
        try await database.open()
        _ = try await database.migrate()
        let result = try await TaskRolloverEngine(root: root, database: database).run(
            date: parsed.date,
            apply: parsed.apply
        )
        await database.close()

        if result.entries.isEmpty {
            print("No tasks to roll over.")
            return
        }

        let action = result.applied ? "Rolled over" : "Would roll over"
        print("\(action) \(result.entries.count) task\(result.entries.count == 1 ? "" : "s") into \(result.targetNotePath)")
        for entry in result.entries {
            print("  \(entry.task.title)  (\(entry.task.notePath):\(entry.task.lineNumber))")
        }
        if !result.applied {
            print("Run again with --apply to update Today's note.")
        }
    }

    private static func parseRolloverArguments(_ arguments: [String]) throws -> ParsedRolloverArguments {
        var date = Date()
        var apply = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--apply":
                apply = true
                index += 1
            case "--date":
                guard index + 1 < arguments.count else { throw CommandError.missingDateValue }
                date = try parseISODate(arguments[index + 1])
                index += 2
            case let flag where flag.hasPrefix("--"):
                throw CommandError.unknownRolloverFlag(flag)
            default:
                throw CommandError.unknownRolloverFlag(arguments[index])
            }
        }

        return ParsedRolloverArguments(date: date, apply: apply)
    }

    /// Read-only review of today's still-open tasks. It rebuilds the local projection from
    /// Markdown first, then filters to the requested daily note.
    private static func runEndOfDay(arguments: [String], root: WorkspaceRoot) async throws {
        let date = try parseDatedReadArguments(arguments, usageError: CommandError.unknownEndOfDayFlag)
        let database = Database(configuration: DatabaseConfiguration(path: databaseURL(for: root).path))
        try await database.open()
        _ = try await database.migrate()
        _ = try await WorkspaceIndexer(root: root, database: database).rebuild()
        let targetPath = DailyNote.relativePath(for: date)
        let tasks = try await database.openTasks().filter { $0.notePath == targetPath }
        await database.close()

        let label = (targetPath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        guard !tasks.isEmpty else {
            print("No still-open tasks for \(label).")
            return
        }

        print("Still open for \(label) (\(tasks.count) task\(tasks.count == 1 ? "" : "s"))")
        for task in tasks {
            print("  \(task.title)  (\(task.notePath):\(task.lineNumber))")
        }
    }

    private static func parseDatedReadArguments(
        _ arguments: [String],
        usageError: (String) -> CommandError
    ) throws -> Date {
        var date = Date()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--date":
                guard index + 1 < arguments.count else { throw CommandError.missingDateValue }
                date = try parseISODate(arguments[index + 1])
                index += 2
            case let flag where flag.hasPrefix("--"):
                throw usageError(flag)
            default:
                throw usageError(arguments[index])
            }
        }

        return date
    }

    /// Read-only. Lists open tasks from the index, grouped into Open Loops buckets. It never
    /// writes Markdown or rolls tasks forward; run `daymark rebuild` first to refresh the index.
    private static func runOpenLoops(root: WorkspaceRoot) async throws {
        let database = Database(configuration: DatabaseConfiguration(path: databaseURL(for: root).path))
        try await database.open()
        _ = try await database.migrate()
        let tasks = try await database.openTasks()
        await database.close()

        let groups = OpenLoops.grouped(tasks: tasks, on: Date())
        let total = groups.reduce(0) { $0 + $1.tasks.count }
        guard total > 0 else {
            print("No open tasks. Run `daymark rebuild` to index your notes, then capture some with `daymark capture --task`.")
            return
        }

        print("Open Loops (\(total) open task\(total == 1 ? "" : "s"))")
        for group in groups {
            print("")
            print(group.bucket.title)
            for task in group.tasks {
                print("  \(task.title)  (\(task.notePath):\(task.lineNumber))")
            }
        }
    }

    private struct ParsedCodexTaskArguments {
        var sourcePath: String?
        var line: Int?
        var selectionFile: String?
        var date: Date = Date()
        var apply = false
    }

    private struct ParsedContextBundleArguments {
        var taskPath: String?
        var date: Date = Date()
        var apply = false
    }

    /// Creates a previewed Codex task draft from a source note line or explicit selection
    /// file. Dry-run prints the exact Markdown; `--apply` writes one file under specs/tasks.
    private static func runCodexTask(arguments: [String], root: WorkspaceRoot) throws {
        let parsed = try parseCodexTaskArguments(arguments)
        guard let sourcePath = parsed.sourcePath else { throw CommandError.missingCodexTaskSource }

        let sourceURL = resolveWorkspaceFile(sourcePath, root: root)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CommandError.sourceNotFound(sourcePath)
        }
        let sourceMarkdown = try String(contentsOf: sourceURL, encoding: .utf8)
        if let line = parsed.line, line > lineCount(in: sourceMarkdown) {
            throw CommandError.invalidLineValue("\(line)")
        }

        let selection: SourceSelection
        if let selectionFile = parsed.selectionFile {
            let selectedText = try String(contentsOfFile: selectionFile, encoding: .utf8)
            let sourceLine = parsed.line
            selection = SourceSelection(
                excerpt: selectedText,
                sourcePath: sourcePath,
                startLine: sourceLine,
                endLine: sourceLine,
                heading: nil
            )
        } else {
            guard let line = parsed.line else { throw CommandError.missingCodexTaskLine }
            let cursor = cursorLocation(forLine: line, in: sourceMarkdown)
            selection = try SourceSelector().select(
                text: sourceMarkdown,
                selectedRange: NSRange(location: cursor, length: 0),
                cursorLocation: cursor,
                sourcePath: sourcePath
            )
        }

        let draft = try PreviewBuilder().codexTaskPreview(
            source: selection,
            date: parsed.date,
            existingRelativePaths: existingCodexTaskPaths(root: root)
        )

        if parsed.apply {
            let result = try CodexTaskFileWriter().write(draft, root: root)
            print("Created: \(result.relativePath)")
        } else {
            print("Target: \(draft.suggestedFilePath)")
            print("")
            print(draft.markdown(), terminator: "")
        }
    }

    private static func parseCodexTaskArguments(_ arguments: [String]) throws -> ParsedCodexTaskArguments {
        var parsed = ParsedCodexTaskArguments()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--source":
                guard index + 1 < arguments.count else { throw CommandError.missingCodexTaskSource }
                parsed.sourcePath = arguments[index + 1]
                index += 2
            case "--line":
                guard index + 1 < arguments.count, let line = Int(arguments[index + 1]), line > 0 else {
                    throw CommandError.invalidLineValue(arguments[safe: index + 1] ?? "")
                }
                parsed.line = line
                index += 2
            case "--selection-file":
                guard index + 1 < arguments.count else { throw CommandError.missingSelectionFile }
                parsed.selectionFile = arguments[index + 1]
                index += 2
            case "--date":
                guard index + 1 < arguments.count else { throw CommandError.missingDateValue }
                parsed.date = try parseISODate(arguments[index + 1])
                index += 2
            case "--apply":
                parsed.apply = true
                index += 1
            case let flag where flag.hasPrefix("--"):
                throw CommandError.unknownCodexTaskFlag(flag)
            default:
                throw CommandError.unknownCodexTaskFlag(arguments[index])
            }
        }

        return parsed
    }

    private static func resolveWorkspaceFile(_ path: String, root: WorkspaceRoot) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return root.expandedURL.appendingPathComponent(path)
    }

    private static func cursorLocation(forLine lineNumber: Int, in text: String) -> Int {
        guard lineNumber > 1 else { return 0 }
        var currentLine = 1
        var location = 0
        for scalar in text.unicodeScalars {
            if currentLine == lineNumber { break }
            location += String(scalar).utf16.count
            if scalar == "\n" {
                currentLine += 1
            }
        }
        return min(location, (text as NSString).length)
    }

    private static func lineCount(in text: String) -> Int {
        max(1, text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .count)
    }

    private static func existingCodexTaskPaths(root: WorkspaceRoot) -> Set<String> {
        let directory = root.expandedURL.appendingPathComponent("specs/tasks", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return Set(files.filter { $0.pathExtension == "md" }.map { "specs/tasks/\($0.lastPathComponent)" })
    }

    private static func runContextBundle(arguments: [String], root: WorkspaceRoot) throws {
        let parsed = try parseContextBundleArguments(arguments)
        guard let taskPath = parsed.taskPath else { throw CommandError.missingContextBundleTask }
        let taskURL = resolveWorkspaceFile(taskPath, root: root)
        guard FileManager.default.fileExists(atPath: taskURL.path) else {
            throw CommandError.contextBundleTaskNotFound(taskPath)
        }
        let markdown = try String(contentsOf: taskURL, encoding: .utf8)
        let draft = try draftFromCodexTaskMarkdown(markdown, taskRelativePath: taskPath)
        let bundle = CodexContextBundle.from(
            draft: draft,
            taskRelativePath: taskPath,
            date: parsed.date,
            existingRelativePaths: existingContextBundlePaths(root: root)
        )

        if parsed.apply {
            let result = try CodexContextBundleWriter().write(bundle, root: root)
            print("Created: \(result.relativePath)")
        } else {
            print("Target: \(bundle.suggestedFilePath)")
            print("")
            print(bundle.markdown(), terminator: "")
        }
    }

    private static func parseContextBundleArguments(_ arguments: [String]) throws -> ParsedContextBundleArguments {
        var parsed = ParsedContextBundleArguments()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--task":
                guard index + 1 < arguments.count else { throw CommandError.missingContextBundleTask }
                parsed.taskPath = arguments[index + 1]
                index += 2
            case "--date":
                guard index + 1 < arguments.count else { throw CommandError.missingDateValue }
                parsed.date = try parseISODate(arguments[index + 1])
                index += 2
            case "--apply":
                parsed.apply = true
                index += 1
            case let flag where flag.hasPrefix("--"):
                throw CommandError.unknownContextBundleFlag(flag)
            default:
                throw CommandError.unknownContextBundleFlag(arguments[index])
            }
        }

        return parsed
    }

    private static func draftFromCodexTaskMarkdown(_ markdown: String, taskRelativePath: String) throws -> CodexTaskDraft {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let title = lines
            .first { $0.hasPrefix("# ") }?
            .dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let goal = section("Goal", in: lines).trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLines = section("Source", in: lines)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let sourcePath = sourceLines.compactMap { sourceValue(prefix: "Path:", line: $0) }.first ?? ""
        let lineRange = sourceLines.compactMap { sourceLineRange(from: $0) }.first
        let sourceBlock = sourceLines.compactMap { sourceValue(prefix: "Block:", line: $0) }.first
        let excerpt = unfenced(section("Source Excerpt", in: lines))
        let constraints = CodexTaskDraft.cleanedListItems(
            section("Constraints", in: lines).components(separatedBy: "\n")
        )
        let criteria = CodexTaskDraft.cleanedListItems(
            section("Acceptance Criteria", in: lines).components(separatedBy: "\n")
        )

        let draft = CodexTaskDraft(
            title: title,
            goal: goal,
            sourcePath: sourcePath,
            sourceLine: lineRange?.start,
            sourceEndLine: lineRange?.end,
            sourceBlock: sourceBlock,
            sourceExcerpt: excerpt,
            constraints: constraints,
            suggestedFilePath: taskRelativePath,
            acceptanceCriteria: criteria
        )
        do {
            try CodexTaskFileWriter().validate(draft)
        } catch {
            throw CommandError.invalidContextBundleTask(taskRelativePath)
        }
        return draft
    }

    private static func section(_ name: String, in lines: [String]) -> String {
        let heading = "## \(name)"
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else {
            return ""
        }
        let bodyStart = start + 1
        let bodyEnd = lines[bodyStart...].firstIndex { line in
            line.hasPrefix("## ")
        } ?? lines.endIndex
        return lines[bodyStart..<bodyEnd].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sourceValue(prefix: String, line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let raw = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("`"), raw.hasSuffix("`"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        return raw.isEmpty ? nil : raw
    }

    private static func sourceLineRange(from line: String) -> (start: Int, end: Int?)? {
        if let value = sourceValue(prefix: "Line:", line: line), let number = Int(value) {
            return (number, nil)
        }
        guard let value = sourceValue(prefix: "Lines:", line: line) else { return nil }
        let parts = value.split(separator: "-", maxSplits: 1)
        guard let start = parts.first.flatMap({ Int($0) }) else { return nil }
        let end = parts.dropFirst().first.flatMap { Int($0) }
        return (start, end)
    }

    private static func unfenced(_ value: String) -> String {
        let lines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces),
              let last = lines.last?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("```"),
              last == "```",
              lines.count >= 2 else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func existingContextBundlePaths(root: WorkspaceRoot) -> Set<String> {
        let directory = root.expandedURL.appendingPathComponent("artifacts/context-bundles", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return Set(files.filter { $0.pathExtension == "md" }.map { "artifacts/context-bundles/\($0.lastPathComponent)" })
    }

    /// Runs a local full-text search over the index and prints matching notes.
    private static func runSearch(arguments: [String], root: WorkspaceRoot) async throws {
        var terms: [String] = []
        var index = 0
        while index < arguments.count {
            terms.append(arguments[index])
            index += 1
        }

        let query = terms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw CommandError.missingSearchQuery }

        let database = Database(configuration: DatabaseConfiguration(path: databaseURL(for: root).path))
        try await database.open()
        _ = try await database.migrate()
        let hits = try await database.search(query, limit: 20)
        await database.close()

        if hits.isEmpty {
            print("No matches for \"\(query)\". Run `daymark index` or `daymark rebuild` first.")
            return
        }
        for hit in hits {
            print(hit.relativePath)
            if !hit.snippet.isEmpty {
                print("    \(hit.snippet)")
            }
        }
    }

    /// Read-only. Prints today's note from disk, or the template it would be created from.
    private static func runToday(root: WorkspaceRoot) throws {
        let store = DailyNoteStore(root: root)
        let url = store.todayFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            print(try store.loadToday())
        } else {
            print(DailyNote.defaultTemplate(for: Date()))
        }
    }

    // MARK: - Helpers

    private static func databaseURL(for root: WorkspaceRoot) -> URL {
        root.expandedURL.appendingPathComponent(".daymark/daymark.db")
    }

    private static func printUsage(to file: FileHandle = .standardOutput, message: String? = nil) {
        if let message {
            file.write(Data("\(message)\n\n".utf8))
        }

        file.write(Data(("""
        daymark

        Commands:
          doctor      Read-only workspace and index health check
          init        Create workspace directories and today's note
          index       Project today's note into the index database
          rebuild     Rebuild the index from every daily Markdown file
          capture     Capture text to the monthly Slip file, or to today's note
          rollover    Roll open prior tasks into Today's Brief
          end-of-day  List today's still-open tasks
          open-loops  List open tasks grouped into buckets (read-only)
          codex-task  Preview or write one Codex task file from note text
          context-bundle  Preview or write one context bundle from a Codex task file
          search      Search notes locally with full-text search
          today       Print today's note (or the template it would use)

        Capture:
          daymark capture <text>            Append to this month's slip/YYYY-MM.md
          daymark capture --today <text>    Append under today's ## Capture
          daymark capture --task <text>     Append as an open task under ## Capture
          (text may also be piped on stdin)

        Codex task:
          daymark codex-task --source <path> --line <n>
          daymark codex-task --source <path> --selection-file <path> --apply

        Context bundle:
          daymark context-bundle --task specs/tasks/<file>.md
          daymark context-bundle --task specs/tasks/<file>.md --apply

        Options:
          --root <path>   Workspace root (default: $DAYMARK_WORKSPACE_ROOT or ~/phoenix)
        """ + "\n").utf8)
    )
    }

    private static func parseCommandAndRootOptions(_ arguments: [String]) throws -> (command: String, options: [String], root: WorkspaceRoot) {
        var command = "help"
        var optionsWithoutRoot: [String] = []
        var rootOverride: String?

        var index = 0
        while index < arguments.count {
            if arguments[index] == "--root" {
                guard index + 1 < arguments.count else {
                    throw CommandError.missingRootValue
                }
                rootOverride = arguments[index + 1]
                index += 2
                continue
            }

            if command == "help" {
                command = arguments[index]
                index += 1
                continue
            }

            optionsWithoutRoot.append(arguments[index])
            index += 1
        }

        return (command, optionsWithoutRoot, WorkspaceRoot.resolve(override: rootOverride))
    }

    private static func parseISODate(_ value: String) throws -> Date {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw CommandError.invalidDate(value)
        }

        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = components.date,
              DailyNote.relativePath(for: date) == String(format: "daily/%04d/%02d/%04d-%02d-%02d.md", year, month, year, month, day) else {
            throw CommandError.invalidDate(value)
        }
        return date
    }

    private static var isStandardInputTerminal: Bool {
        isatty(STDIN_FILENO) == 1
    }

    private static var standardInputText: String? {
        if isStandardInputTerminal {
            return nil
        }

        var data = Data()
        while true {
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }

        guard !data.isEmpty, let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private enum CommandError: LocalizedError {
        case unknownCommand(String)
        case missingCaptureText
        case unknownCaptureFlag(String)
        case captureOptionsConflict([String])
        case unknownRolloverFlag(String)
        case unknownEndOfDayFlag(String)
        case unknownCodexTaskFlag(String)
        case unknownContextBundleFlag(String)
        case missingDateValue
        case invalidDate(String)
        case missingCodexTaskSource
        case missingCodexTaskLine
        case missingSelectionFile
        case invalidLineValue(String)
        case missingContextBundleTask
        case contextBundleTaskNotFound(String)
        case invalidContextBundleTask(String)
        case sourceNotFound(String)
        case missingSearchQuery
        case missingRootValue

        var usage: String? {
            switch self {
            case .missingCaptureText,
                 .unknownCaptureFlag,
                 .captureOptionsConflict:
                return "Usage: daymark capture [--today | --task] <text>   (or pipe text on stdin)"
            case .unknownRolloverFlag:
                return "Usage: daymark rollover [--date yyyy-MM-dd] [--apply]"
            case .missingDateValue,
                 .invalidDate:
                return "Usage: daymark <rollover|end-of-day> [--date yyyy-MM-dd]"
            case .unknownEndOfDayFlag:
                return "Usage: daymark end-of-day [--date yyyy-MM-dd]"
            case .missingCodexTaskSource,
                 .missingCodexTaskLine,
                 .missingSelectionFile,
                 .invalidLineValue,
                 .sourceNotFound,
                 .unknownCodexTaskFlag:
                return "Usage: daymark codex-task --source <path> (--line <n> | --selection-file <path>) [--date yyyy-MM-dd] [--apply]"
            case .missingContextBundleTask,
                 .contextBundleTaskNotFound,
                 .invalidContextBundleTask,
                 .unknownContextBundleFlag:
                return "Usage: daymark context-bundle --task specs/tasks/<file>.md [--date yyyy-MM-dd] [--apply]"
            case .unknownCommand:
                return "Usage: daymark <doctor|init|index|rebuild|capture|rollover|end-of-day|open-loops|codex-task|context-bundle|search|today>"
            case .missingSearchQuery:
                return "Usage: daymark search <query>"
            case .missingRootValue:
                return "Usage: daymark [--root <path>] <command>"
            }
        }

        var errorDescription: String? {
            switch self {
            case .unknownCommand(let command):
                return "unknown command: \(command)"
            case .missingCaptureText:
                return "capture text is required"
            case .unknownCaptureFlag(let flag):
                return "unknown flag: \(flag)"
            case .captureOptionsConflict(let flags):
                return "conflicting capture flags: \(flags.joined(separator: " and ")) are mutually exclusive"
            case .unknownRolloverFlag(let flag):
                return "unknown rollover flag: \(flag)"
            case .unknownEndOfDayFlag(let flag):
                return "unknown end-of-day flag: \(flag)"
            case .unknownCodexTaskFlag(let flag):
                return "unknown codex-task flag: \(flag)"
            case .unknownContextBundleFlag(let flag):
                return "unknown context-bundle flag: \(flag)"
            case .missingDateValue:
                return "--date requires a yyyy-MM-dd value"
            case .invalidDate(let value):
                return "invalid date: \(value)"
            case .missingCodexTaskSource:
                return "--source is required"
            case .missingCodexTaskLine:
                return "--line is required when --selection-file is not provided"
            case .missingSelectionFile:
                return "--selection-file requires a path"
            case .invalidLineValue(let value):
                return "invalid line: \(value)"
            case .missingContextBundleTask:
                return "--task is required"
            case .contextBundleTaskNotFound(let path):
                return "task file not found: \(path)"
            case .invalidContextBundleTask(let path):
                return "invalid Codex task file: \(path)"
            case .sourceNotFound(let path):
                return "source not found: \(path)"
            case .missingSearchQuery:
                return "search query is required"
            case .missingRootValue:
                return "--root requires a value"
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
