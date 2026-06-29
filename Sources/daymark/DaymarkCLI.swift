import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import DaymarkCore
import DaymarkStore
import DaymarkIndexer

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
          search      Search notes locally with full-text search
          today       Print today's note (or the template it would use)

        Capture:
          daymark capture <text>            Append to this month's slip/YYYY-MM.md
          daymark capture --today <text>    Append under today's ## Capture
          daymark capture --task <text>     Append as an open task under ## Capture
          (text may also be piped on stdin)

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
        case missingDateValue
        case invalidDate(String)
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
            case .unknownCommand:
                return "Usage: daymark <doctor|init|index|rebuild|capture|rollover|end-of-day|open-loops|search|today>"
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
            case .missingDateValue:
                return "--date requires a yyyy-MM-dd value"
            case .invalidDate(let value):
                return "invalid date: \(value)"
            case .missingSearchQuery:
                return "search query is required"
            case .missingRootValue:
                return "--root requires a value"
            }
        }
    }
}
