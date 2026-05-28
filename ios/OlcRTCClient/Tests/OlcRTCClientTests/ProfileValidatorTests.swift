import XCTest

final class ProfileValidatorTests: XCTestCase {
    private let validator = ProfileValidator()
    private let validKey64 = "d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799"

    func test_validProfileHasNoIssues() {
        let issues = validator.validate(
            provider: "wbstream",
            transport: "datachannel",
            roomID: "room-01",
            clientID: "alice",
            keyHex: validKey64,
            socksHost: "127.0.0.1",
            socksPortString: "8808",
            dnsServer: "8.8.8.8:53"
        )
        XCTAssertTrue(issues.isEmpty, "expected no issues, got \(issues)")
    }

    func test_rejectsUnknownProvider() {
        let issues = validator.validate(
            provider: "zoom",
            transport: "datachannel",
            roomID: "room",
            clientID: "alice",
            keyHex: validKey64,
            socksHost: "127.0.0.1",
            socksPortString: "8808",
            dnsServer: ""
        )
        XCTAssertTrue(issues.contains(where: { $0.field == .provider }), "got \(issues)")
    }

    func test_rejectsUnknownTransport() {
        let issues = validator.validate(
            provider: "wbstream",
            transport: "webrtc",
            roomID: "room",
            clientID: "alice",
            keyHex: validKey64,
            socksHost: "127.0.0.1",
            socksPortString: "8808",
            dnsServer: ""
        )
        XCTAssertTrue(issues.contains(where: { $0.field == .transport }))
    }

    func test_rejectsEmptyRoom_andEmptyClientID() {
        let issues = validator.validate(
            provider: "wbstream",
            transport: "datachannel",
            roomID: "   ",
            clientID: "",
            keyHex: validKey64,
            socksHost: "127.0.0.1",
            socksPortString: "8808",
            dnsServer: ""
        )
        XCTAssertTrue(issues.contains(where: { $0.field == .roomID }))
        XCTAssertTrue(issues.contains(where: { $0.field == .clientID }))
    }

    func test_rejectsShortKey() {
        let issues = validator.validate(
            provider: "wbstream",
            transport: "datachannel",
            roomID: "room",
            clientID: "alice",
            keyHex: "deadbeef",
            socksHost: "127.0.0.1",
            socksPortString: "8808",
            dnsServer: ""
        )
        XCTAssertTrue(issues.contains(where: { $0.field == .keyHex }))
    }

    func test_rejectsNonHexKey() {
        let badKey = String(repeating: "g", count: 64)
        let issues = validator.validate(
            provider: "wbstream",
            transport: "datachannel",
            roomID: "room",
            clientID: "alice",
            keyHex: badKey,
            socksHost: "127.0.0.1",
            socksPortString: "8808",
            dnsServer: ""
        )
        XCTAssertTrue(issues.contains(where: { $0.field == .keyHex }))
    }

    func test_acceptsUppercaseKey() {
        let issues = validator.validate(
            provider: "wbstream",
            transport: "datachannel",
            roomID: "room",
            clientID: "alice",
            keyHex: validKey64.uppercased(),
            socksHost: "127.0.0.1",
            socksPortString: "8808",
            dnsServer: ""
        )
        XCTAssertFalse(issues.contains(where: { $0.field == .keyHex }), "got \(issues)")
    }

    func test_rejectsBadPort() {
        for raw in ["", "0", "65536", "abc", "-1", "8.8"] {
            let issues = validator.validate(
                provider: "wbstream",
                transport: "datachannel",
                roomID: "room",
                clientID: "alice",
                keyHex: validKey64,
                socksHost: "127.0.0.1",
                socksPortString: raw,
                dnsServer: ""
            )
            XCTAssertTrue(
                issues.contains(where: { $0.field == .socksPort }),
                "expected port '\(raw)' to be rejected"
            )
        }
    }

    func test_acceptsPortBoundaries() {
        for raw in ["1", "65535", "8080"] {
            let issues = validator.validate(
                provider: "wbstream",
                transport: "datachannel",
                roomID: "room",
                clientID: "alice",
                keyHex: validKey64,
                socksHost: "127.0.0.1",
                socksPortString: raw,
                dnsServer: ""
            )
            XCTAssertFalse(
                issues.contains(where: { $0.field == .socksPort }),
                "expected port '\(raw)' to be accepted, got \(issues)"
            )
        }
    }
}
