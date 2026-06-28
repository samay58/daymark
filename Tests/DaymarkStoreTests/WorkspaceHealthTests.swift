import XCTest
import DaymarkCore
@testable import DaymarkStore

final class WorkspaceHealthTests: XCTestCase {
    private func makeTempRoot() throws -> WorkspaceRoot {
        let dir = "\(NSTemporaryDirectory())daymark-health-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return WorkspaceRoot(path: dir)
    }

    func testInspectReportsEmptyWorkspaceAndCreatesNothing() throws {
        let root = try makeTempRoot()
        let health = WorkspaceHealth.inspect(root: root)

        XCTAssertFalse(health.isBootstrapped)
        XCTAssertEqual(health.missingDirectoryCount, WorkspaceBootstrapper.requiredRelativeDirectories.count)
        XCTAssertFalse(health.todayNoteExists)
        XCTAssertFalse(health.databaseExists)
        XCTAssertEqual(health.declaredMigrations, ["001_initial_schema.sql", "002_note_search.sql"])

        // Inspection must be read-only.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.expandedPath),
                       "inspect must not create the workspace")
    }

    func testInspectReflectsBootstrapAndTodayNote() throws {
        let root = try makeTempRoot()
        _ = try WorkspaceBootstrapper().bootstrap(root: root)
        _ = try DailyNoteStore(root: root).ensureTodayNote()

        let health = WorkspaceHealth.inspect(root: root)
        XCTAssertTrue(health.isBootstrapped)
        XCTAssertEqual(health.missingDirectoryCount, 0)
        XCTAssertTrue(health.todayNoteExists)
        XCTAssertEqual(health.dailyMarkdownCount, 1)
        XCTAssertTrue(health.databasePath.hasSuffix(".daymark/daymark.db"))
        XCTAssertFalse(health.databaseExists, "doctor must not require or create the database")
    }

    func testDatabasePresenceIsDetected() async throws {
        let root = try makeTempRoot()
        _ = try WorkspaceBootstrapper().bootstrap(root: root)
        let database = Database(configuration: DatabaseConfiguration(path: WorkspaceHealth.inspect(root: root).databasePath))
        try await database.open()
        _ = try await database.migrate()
        await database.close()

        XCTAssertTrue(WorkspaceHealth.inspect(root: root).databaseExists)
    }
}
