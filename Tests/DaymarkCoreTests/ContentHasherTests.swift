import XCTest
@testable import DaymarkCore

final class ContentHasherTests: XCTestCase {
    func testHashIsStableAcrossCalls() {
        XCTAssertEqual(ContentHasher.hash("# Today\n\nBody"), ContentHasher.hash("# Today\n\nBody"))
    }

    func testDifferentContentProducesDifferentHash() {
        XCTAssertNotEqual(ContentHasher.hash("one"), ContentHasher.hash("two"))
    }

    func testHashMatchesKnownSha256() {
        // sha256("daymark") lowercase hex, a fixed vector so the hash is reproducible across runs.
        XCTAssertEqual(
            ContentHasher.hash("daymark"),
            "6faf156297b2e3d8da727e5fb2f055a2bb7450be1de40af19156c1ad17ac90ab"
        )
    }
}
