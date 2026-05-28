import XCTest

final class LogSanitizerTests: XCTestCase {
    private let sanitizer = LogSanitizer()

    func test_masksRealKeyHex() {
        let key = "d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799"
        let input = "starting with key \(key) ok"
        let out = sanitizer.sanitize(input)
        XCTAssertFalse(out.contains(key))
        XCTAssertTrue(out.contains("<keyHex:masked>"))
    }

    func test_masksOlcRTCURIIncludingKey() {
        let uri = "olcrtc://wbstream?datachannel@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799$RU"
        let input = "imported \(uri) now"
        let out = sanitizer.sanitize(input)
        XCTAssertFalse(out.contains("d823fa01cb3e0609"))
        XCTAssertTrue(out.contains("<olcrtc-uri:masked>") || out.contains("<keyHex:masked>"))
    }

    func test_masksKeyHexAssignment() {
        let out = sanitizer.sanitize("config keyHex=abc123 user=alice")
        XCTAssertTrue(out.contains("keyHex=<masked>"))
        XCTAssertTrue(out.contains("user=alice"))
    }

    func test_masksPasswordAssignment() {
        let out = sanitizer.sanitize("auth password=hunter2 verb=login")
        XCTAssertFalse(out.contains("hunter2"))
        XCTAssertTrue(out.contains("password=<masked>"))
    }

    func test_passesThroughNonSensitive() {
        let line = "starting transport=datachannel provider=wbstream room=room-01"
        XCTAssertEqual(sanitizer.sanitize(line), line)
    }

    func test_shortHexIsNotMasked() {
        // 16 hex chars — below our defensive 32-char threshold; should pass.
        let input = "id=deadbeefcafef00d done"
        XCTAssertEqual(sanitizer.sanitize(input), input)
    }
}
