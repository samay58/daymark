import XCTest
import DaymarkCore
@testable import DaymarkStore

final class SearchTests: XCTestCase {
    private func makeMigratedRepository() async throws -> NoteRepository {
        let path = "\(NSTemporaryDirectory())daymark-search-\(UUID().uuidString)/daymark.db"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
        let db = Database(configuration: DatabaseConfiguration(path: path))
        try await db.open()
        _ = try await db.migrate()
        return NoteRepository(database: db)
    }

    private func project(_ repo: NoteRepository, path: String, title: String, body: String) async throws {
        try await repo.projectNote(
            relativePath: path,
            title: title,
            content: body,
            modifiedAt: nil,
            blocks: [Block(id: "l1", markdown: body, lineStart: 1, lineEnd: 1)]
        )
    }

    func testSearchMatchesBodyText() async throws {
        let repo = try await makeMigratedRepository()
        try await project(repo, path: "daily/a.md", title: "Monday", body: "Implement local search for notes")
        try await project(repo, path: "daily/b.md", title: "Tuesday", body: "Buy oat milk and bananas")

        let hits = try await repo.search("search")
        XCTAssertEqual(hits.map(\.relativePath), ["daily/a.md"])
    }

    func testSearchSnippetIsPopulated() async throws {
        let repo = try await makeMigratedRepository()
        try await project(repo, path: "daily/a.md", title: "Note", body: "the quick brown fox jumps")
        let hits = try await repo.search("brown")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits.first?.snippet.contains("brown") ?? false)
    }

    func testSearchSupportsPrefixMatching() async throws {
        let repo = try await makeMigratedRepository()
        try await project(repo, path: "daily/a.md", title: "Planning", body: "onboarding flow design")

        let hits = try await repo.search("onboard")
        XCTAssertEqual(hits.first?.relativePath, "daily/a.md")
    }

    func testReprojectingUpdatesSearchInsteadOfDuplicating() async throws {
        let repo = try await makeMigratedRepository()
        try await project(repo, path: "daily/a.md", title: "v1", body: "alpha content")
        try await project(repo, path: "daily/a.md", title: "v2", body: "bravo content")

        let stale = try await repo.search("alpha").count
        let fresh = try await repo.search("bravo").count
        XCTAssertEqual(stale, 0, "stale body must not remain searchable")
        XCTAssertEqual(fresh, 1)
    }

    func testRemovingNoteDropsItFromSearch() async throws {
        let repo = try await makeMigratedRepository()
        try await project(repo, path: "daily/a.md", title: "Gone", body: "ephemeral note")
        try await repo.removeNote(relativePath: "daily/a.md")

        let hitCount = try await repo.search("ephemeral").count
        let noteCount = try await repo.database.noteCount()
        XCTAssertEqual(hitCount, 0)
        XCTAssertEqual(noteCount, 0)
    }

    func testBlankQueryReturnsNothing() async throws {
        let repo = try await makeMigratedRepository()
        try await project(repo, path: "daily/a.md", title: "Note", body: "real content")
        let count = try await repo.search("   ").count
        XCTAssertEqual(count, 0)
    }
}
