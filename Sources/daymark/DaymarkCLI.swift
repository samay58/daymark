import Foundation
import DaymarkCore
import DaymarkStore
import DaymarkIndexer

@main
struct DaymarkCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"
        let options = Array(arguments.dropFirst())
        let root = resolveRoot(from: options)

        do {
            switch command {
            case "doctor":
                runDoctor(root: root)
            case "init":
                try runInit(root: root)
            case "index":
                try await runIndex(root: root)
            case "rebuild":
                try await runRebuild(root: root)
            case "search":
                try await runSearch(arguments: options, root: root)
            case "today":
                try runToday(root: root)
            default:
                printUsage()
            }
        } catch {
            FileHandle.standardError.write(Data("daymark \(command): \(error)\n".utf8))
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

    /// Runs a local full-text search over the index and prints matching notes.
    private static func runSearch(arguments: [String], root: WorkspaceRoot) async throws {
        var terms: [String] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--root" {
                index += 2
                continue
            }
            terms.append(arguments[index])
            index += 1
        }

        let query = terms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            print("Usage: daymark search <query>")
            return
        }

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

    private static func resolveRoot(from options: [String]) -> WorkspaceRoot {
        if let index = options.firstIndex(of: "--root"), index + 1 < options.count {
            return WorkspaceRoot.resolve(override: options[index + 1])
        }
        return WorkspaceRoot.resolve()
    }

    private static func databaseURL(for root: WorkspaceRoot) -> URL {
        root.expandedURL.appendingPathComponent(".daymark/daymark.db")
    }

    private static func printUsage() {
        print("""
        daymark

        Commands:
          doctor    Read-only workspace and index health check
          init      Create workspace directories and today's note
          index     Project today's note into the index database
          rebuild   Rebuild the index from every daily Markdown file
          search    Search notes locally with full-text search
          today     Print today's note (or the template it would use)

        Options:
          --root <path>   Workspace root (default: $DAYMARK_WORKSPACE_ROOT or ~/phoenix)
        """)
    }
}
