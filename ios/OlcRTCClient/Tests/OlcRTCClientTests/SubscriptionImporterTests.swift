import XCTest

final class SubscriptionImporterTests: XCTestCase {
    private let importer = SubscriptionImporter()
    private let url = URL(string: "https://example.com/sub.txt")!
    private let validKey64 = "d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799"

    func test_parsesMultipleValidLines() {
        let body = """
        olcrtc://wbstream?datachannel@room-01#\(validKey64)$one
        olcrtc://jitsi?datachannel@room-02#\(validKey64)$two
        """
        let outcome = importer.parse(body: body, sourceURL: url)
        XCTAssertEqual(outcome.imported.count, 2)
        XCTAssertEqual(outcome.skippedCount, 0)
        XCTAssertEqual(outcome.imported[0].roomID, "room-01")
        XCTAssertEqual(outcome.imported[1].roomID, "room-02")
        XCTAssertEqual(outcome.imported[0].name, "one")
        XCTAssertEqual(outcome.imported[1].name, "two")
    }

    func test_skipsEmptyLinesAndComments() {
        let body = """

        # this is a comment
        olcrtc://wbstream?datachannel@room-01#\(validKey64)

        # trailing comment
        """
        let outcome = importer.parse(body: body, sourceURL: url)
        XCTAssertEqual(outcome.imported.count, 1)
        XCTAssertEqual(outcome.skippedCount, 0)
    }

    func test_skipsInvalidLines_butKeepsValidOnes() {
        let body = """
        olcrtc://wbstream?datachannel@room-01#\(validKey64)
        olcrtc://zoom?datachannel@room-02#\(validKey64)
        this is not a uri at all
        olcrtc://jitsi?datachannel@room-03#deadbeef
        olcrtc://wbstream?vp8channel@room-04#\(validKey64)
        """
        let outcome = importer.parse(body: body, sourceURL: url)
        XCTAssertEqual(outcome.imported.count, 2,
            "expected 2 imported (room-01, room-04), got \(outcome.imported.map(\.roomID))")
        XCTAssertEqual(outcome.skippedCount, 3)
        // Skipped reasons must NOT contain the raw key or the raw URI.
        for reason in outcome.skippedReasons {
            XCTAssertFalse(
                reason.contains(validKey64),
                "skipped reason leaked the encryption key: \(reason)"
            )
            XCTAssertFalse(
                reason.contains("olcrtc://"),
                "skipped reason leaked a raw olcrtc:// URI: \(reason)"
            )
        }
    }

    func test_emptyBodyImportsNothing() {
        let outcome = importer.parse(body: "", sourceURL: url)
        XCTAssertEqual(outcome.imported.count, 0)
        XCTAssertEqual(outcome.skippedCount, 0)
    }
}
