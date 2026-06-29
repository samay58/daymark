import XCTest
import DaymarkCore
@testable import DaymarkStore

final class DatabaseTests: XCTestCase {
    private func makeDatabase() -> Database {
        let path = "\(NSTemporaryDirectory())daymark-db-\(UUID().uuidString)/daymark.db"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
        return Database(configuration: DatabaseConfiguration(path: path))
    }

    func testOpenCreatesDatabaseFile() async throws {
        let db = makeDatabase()
        try await db.open()
        let exists = FileManager.default.fileExists(atPath: db.configuration.path)
        await db.close()
        XCTAssertTrue(exists)
    }

    func testMigrateAppliesAllSchemas() async throws {
        let db = makeDatabase()
        try await db.open()
        let applied = try await db.migrate()
        XCTAssertEqual(applied, ["001_initial_schema.sql", "002_note_search.sql", "003_tasks.sql", "004_rollovers.sql"])
        let names = try await db.appliedMigrationNames()
        XCTAssertEqual(names, ["001_initial_schema.sql", "002_note_search.sql", "003_tasks.sql", "004_rollovers.sql"])
        await db.close()
    }

    func testMigrateIsIdempotent() async throws {
        let db = makeDatabase()
        try await db.open()
        _ = try await db.migrate()
        let secondRun = try await db.migrate()
        XCTAssertEqual(secondRun, [], "already-applied migrations should not run again")
        await db.close()
    }

    func testNotesAndBlocksTablesExist() async throws {
        let db = makeDatabase()
        try await db.open()
        _ = try await db.migrate()
        let tables = try await db.tableNames()
        XCTAssertTrue(tables.contains("notes"))
        XCTAssertTrue(tables.contains("blocks"))
        XCTAssertTrue(tables.contains("schema_migrations"))
        await db.close()
    }
}
