import XCTest
import DaymarkCore
@testable import DaymarkStore

final class RolloverRecordTests: XCTestCase {
    private func makeDatabase() async throws -> Database {
        let path = "\(NSTemporaryDirectory())daymark-rollovers-\(UUID().uuidString)/daymark.db"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
        let db = Database(configuration: DatabaseConfiguration(path: path))
        try await db.open()
        _ = try await db.migrate()
        return db
    }

    private func sourceTask() -> TaskItem {
        TaskItem(
            title: "follow up with Sarah",
            status: .open,
            notePath: "daily/2026/06/2026-06-27.md",
            lineNumber: 5,
            originalLine: "- [ ] follow up with Sarah"
        )
    }

    func testRolloversTableExistsAfterMigrate() async throws {
        let db = try await makeDatabase()
        let tables = try await db.tableNames()
        XCTAssertTrue(tables.contains("rollovers"))
        await db.close()
    }

    func testRecordingRolloverIsIdempotentBySourceKeyAndTargetNote() async throws {
        let db = try await makeDatabase()
        let task = sourceTask()
        let record = RolloverRecord(
            sourceKey: task.sourceKey,
            sourceNotePath: task.notePath,
            sourceLineNumber: task.lineNumber,
            sourceTitle: task.title,
            targetNotePath: "daily/2026/06/2026-06-28.md",
            marker: TaskRollover.marker(for: task)
        )

        let firstInsert = try await db.recordRollover(record)
        let secondInsert = try await db.recordRollover(record)
        let count = try await db.rolloverCount()
        XCTAssertTrue(firstInsert)
        XCTAssertFalse(secondInsert)
        XCTAssertEqual(count, 1)
        await db.close()
    }
}
