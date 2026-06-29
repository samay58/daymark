import XCTest
import DaymarkCore
import DaymarkStore
@testable import DaymarkIndexer

final class WorkspaceIndexerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }

    private func fixedToday() throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28, hour: 9)))
    }

    private func makeBootstrappedWorkspace() throws -> WorkspaceRoot {
        let path = "\(NSTemporaryDirectory())daymark-index-\(UUID().uuidString)"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        let root = WorkspaceRoot(path: path)
        _ = try WorkspaceBootstrapper().bootstrap(root: root)
        return root
    }

    private func makeDatabase(in root: WorkspaceRoot) -> Database {
        let dbPath = root.expandedURL.appendingPathComponent(".daymark/daymark.db").path
        return Database(configuration: DatabaseConfiguration(path: dbPath))
    }

    func testIndexTodayProjectsTodaysNote() async throws {
        let root = try makeBootstrappedWorkspace()
        let store = DailyNoteStore(root: root, calendar: calendar)
        let today = try fixedToday()
        _ = try store.ensureTodayNote(date: today)

        let db = makeDatabase(in: root)
        try await db.open()
        _ = try await db.migrate()

        let indexer = WorkspaceIndexer(root: root, database: db, calendar: calendar)
        try await indexer.indexToday(date: today)

        let noteCount = try await db.noteCount()
        XCTAssertEqual(noteCount, 1)

        let relativePath = DailyNote.relativePath(for: today, calendar: calendar)
        let record = try await db.note(relativePath: relativePath)
        XCTAssertEqual(record?.title, "Sunday, June 28")

        let onDisk = try store.loadToday(date: today)
        XCTAssertEqual(record?.contentHash, ContentHasher.hash(onDisk),
                       "projection hash must match the bytes on disk")

        let blockCount = try await db.blockCount()
        XCTAssertGreaterThan(blockCount, 0)
        await db.close()
    }

    func testIndexProjectsTasksFromTheNote() async throws {
        let root = try makeBootstrappedWorkspace()
        let today = try fixedToday()
        let relativePath = DailyNote.relativePath(for: today, calendar: calendar)
        let url = root.expandedURL.appendingPathComponent(relativePath)
        try AtomicFileWriter().write("""
        # Today

        ## Capture

        - [ ] open task @sarah
        - [x] closed task
        """, to: url)

        let db = makeDatabase(in: root)
        try await db.open()
        _ = try await db.migrate()
        try await WorkspaceIndexer(root: root, database: db, calendar: calendar).indexToday(date: today)

        let open = try await db.openTasks()
        XCTAssertEqual(open.count, 1, "only the open task is surfaced")
        XCTAssertEqual(open[0].title, "open task @sarah")
        XCTAssertEqual(open[0].notePath, relativePath, "tasks are stamped with their source note path")
        XCTAssertEqual(open[0].sectionHeading, "Capture")
        await db.close()
    }

    func testRebuildReprojectsAllDailyNotesFromDisk() async throws {
        let root = try makeBootstrappedWorkspace()
        let store = DailyNoteStore(root: root, calendar: calendar)
        let today = try fixedToday()
        _ = try store.ensureTodayNote(date: today)

        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let yesterdayURL = DailyNote.fileURL(in: root, for: yesterday, calendar: calendar)
        try AtomicFileWriter().write("# Yesterday\n\nLog entry\n", to: yesterdayURL)

        let db = makeDatabase(in: root)
        try await db.open()
        _ = try await db.migrate()

        let indexer = WorkspaceIndexer(root: root, database: db, calendar: calendar)
        let indexed = try await indexer.rebuild()
        XCTAssertEqual(indexed, 2, "rebuild should scan every daily Markdown file")
        let noteCount = try await db.noteCount()
        XCTAssertEqual(noteCount, 2)

        // The projection is a pure function of the files: rebuilding again must not duplicate.
        _ = try await indexer.rebuild()
        let afterSecond = try await db.noteCount()
        XCTAssertEqual(afterSecond, 2, "rebuild must be idempotent, never appending")
        await db.close()
    }

    func testRebuildReconstructsProjectionAfterDatabaseDeleted() async throws {
        let root = try makeBootstrappedWorkspace()
        let store = DailyNoteStore(root: root, calendar: calendar)
        let today = try fixedToday()
        _ = try store.ensureTodayNote(date: today)

        let firstDB = makeDatabase(in: root)
        try await firstDB.open()
        _ = try await firstDB.migrate()
        try await WorkspaceIndexer(root: root, database: firstDB, calendar: calendar).indexToday(date: today)
        await firstDB.close()

        // Drop the entire database, including WAL sidecars, then rebuild from Markdown.
        let dbPath = firstDB.configuration.path
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbPath + suffix)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath))

        let rebuiltDB = makeDatabase(in: root)
        try await rebuiltDB.open()
        _ = try await rebuiltDB.migrate()
        _ = try await WorkspaceIndexer(root: root, database: rebuiltDB, calendar: calendar).rebuild()

        let relativePath = DailyNote.relativePath(for: today, calendar: calendar)
        let record = try await rebuiltDB.note(relativePath: relativePath)
        let onDisk = try store.loadToday(date: today)
        XCTAssertEqual(record?.contentHash, ContentHasher.hash(onDisk),
                       "a rebuilt database must match the Markdown files exactly")
        await rebuiltDB.close()
    }
}
