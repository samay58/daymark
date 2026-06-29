import XCTest
@testable import DaymarkStore

final class MigrationTests: XCTestCase {
    func testDeclaredMigrationsAreOrdered() {
        XCTAssertEqual(
            MigrationRunner().pendingMigrationNames(),
            ["001_initial_schema.sql", "002_note_search.sql", "003_tasks.sql", "004_rollovers.sql"]
        )
    }

    func testMatchExpressionTokenizesAndQuotesInput() {
        XCTAssertEqual(DatabaseMatch.expression(from: "open loops"), "\"open\"* \"loops\"*")
    }

    func testMatchExpressionNeutralizesOperators() {
        // A stray quote or operator must not break the MATCH query.
        XCTAssertEqual(DatabaseMatch.expression(from: "a\"b"), "\"a\"\"b\"*")
        XCTAssertEqual(DatabaseMatch.expression(from: "   "), "")
    }
}

/// Test shim exposing the internal MATCH builder without widening the public API.
enum DatabaseMatch {
    static func expression(from query: String) -> String {
        Database.matchExpression(from: query)
    }
}
