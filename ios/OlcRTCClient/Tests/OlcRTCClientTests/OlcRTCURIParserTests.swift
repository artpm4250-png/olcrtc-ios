import XCTest

final class OlcRTCURIParserTests: XCTestCase {
    private let parser = OlcRTCURIParser()

    func test_parsesWbstreamDatachannelExample() throws {
        let uri = "olcrtc://wbstream?datachannel@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799$RU / olc free sub / IPv6"
        let parsed = try parser.parse(uri)

        XCTAssertEqual(parsed.provider, .wbstream)
        XCTAssertEqual(parsed.transport, .datachannel)
        XCTAssertTrue(parsed.transportPayload.isEmpty)
        XCTAssertEqual(parsed.roomID, "room-01")
        XCTAssertEqual(parsed.keyHex, "d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799")
        XCTAssertEqual(parsed.mimo, "RU / olc free sub / IPv6")
    }

    func test_parsesWbstreamVP8WithPayload() throws {
        let uri = "olcrtc://wbstream?vp8channel<vp8-fps=60&vp8-batch=64>@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799$RU"
        let parsed = try parser.parse(uri)

        XCTAssertEqual(parsed.provider, .wbstream)
        XCTAssertEqual(parsed.transport, .vp8channel)
        XCTAssertEqual(parsed.transportPayload["vp8-fps"], "60")
        XCTAssertEqual(parsed.transportPayload["vp8-batch"], "64")
        XCTAssertEqual(parsed.roomID, "room-01")

        let profile = parsed.toProfile(name: "from URI")
        XCTAssertEqual(profile.vp8FPS, 60)
        XCTAssertEqual(profile.vp8BatchSize, 64)
    }

    func test_parsesJitsiWithURLRoomID() throws {
        let uri = "olcrtc://jitsi?datachannel@https://meet1.arbitr.ru/myroom#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799$RU"
        let parsed = try parser.parse(uri)

        XCTAssertEqual(parsed.provider, .jitsi)
        XCTAssertEqual(parsed.transport, .datachannel)
        XCTAssertEqual(parsed.roomID, "https://meet1.arbitr.ru/myroom")
        XCTAssertEqual(parsed.keyHex, "d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799")
    }

    func test_parsesWithoutMIMO() throws {
        let uri = "olcrtc://wbstream?datachannel@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799"
        let parsed = try parser.parse(uri)
        XCTAssertNil(parsed.mimo)
    }

    func test_rejectsWrongScheme() {
        XCTAssertThrowsError(try parser.parse("https://example.com")) { error in
            XCTAssertEqual(error as? OlcRTCURIParser.ParseError, .wrongScheme)
        }
    }

    func test_rejectsUnknownProvider() {
        let uri = "olcrtc://nopesuch?datachannel@room#deadbeef"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            guard case .unknownProvider(let name)? = error as? OlcRTCURIParser.ParseError else {
                return XCTFail("Expected unknownProvider, got \(error)")
            }
            XCTAssertEqual(name, "nopesuch")
        }
    }

    func test_rejectsUnknownTransport() {
        let uri = "olcrtc://wbstream?noway@room#deadbeef"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            guard case .unknownTransport? = error as? OlcRTCURIParser.ParseError else {
                return XCTFail("Expected unknownTransport, got \(error)")
            }
        }
    }

    func test_rejectsMissingRoomSeparator() {
        let uri = "olcrtc://wbstream?datachannel#deadbeef"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            XCTAssertEqual(error as? OlcRTCURIParser.ParseError, .missingRoomSeparator)
        }
    }

    func test_rejectsMissingKeySeparator() {
        let uri = "olcrtc://wbstream?datachannel@room-01"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            XCTAssertEqual(error as? OlcRTCURIParser.ParseError, .missingKeySeparator)
        }
    }

    // MARK: - 2026-05-28 hardening: percent-decoding, key validation, MIMO-as-name

    private let validKey64 = "d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799"

    func test_parsesJitsiDatachannel_canonical() throws {
        let uri = "olcrtc://jitsi?datachannel@room-01#\(validKey64)$JitsiProfile"
        let parsed = try parser.parse(uri)
        XCTAssertEqual(parsed.provider, .jitsi)
        XCTAssertEqual(parsed.transport, .datachannel)
        XCTAssertEqual(parsed.roomID, "room-01")
        XCTAssertEqual(parsed.keyHex, validKey64)
        // MIMO is now used as the default display name.
        XCTAssertEqual(parsed.toProfile(name: "fallback").name, "JitsiProfile")
    }

    func test_parsesWbstreamVP8Channel_canonical() throws {
        let uri = "olcrtc://wbstream?vp8channel@room-01#\(validKey64)$WB"
        let parsed = try parser.parse(uri)
        XCTAssertEqual(parsed.provider, .wbstream)
        XCTAssertEqual(parsed.transport, .vp8channel)
        XCTAssertEqual(parsed.roomID, "room-01")
    }

    func test_percentDecodesRoomAndMimo() throws {
        // Room contains percent-encoded space; MIMO contains percent-encoded slash.
        let uri = "olcrtc://wbstream?datachannel@room%20with%20space#\(validKey64)$RU%20%2F%20free"
        let parsed = try parser.parse(uri)
        XCTAssertEqual(parsed.roomID, "room with space")
        XCTAssertEqual(parsed.mimo, "RU / free")
    }

    func test_rejectsInvalidKeyLength() {
        // 32 hex chars — half the required length, but still pure hex.
        // Should fail the new strict length check, NOT be masked away.
        let shortKey = "d823fa01cb3e0609b67322f7cf984c4e"
        let uri = "olcrtc://wbstream?datachannel@room-01#\(shortKey)"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            guard case .invalidKeyHex? = error as? OlcRTCURIParser.ParseError else {
                return XCTFail("Expected invalidKeyHex, got \(error)")
            }
        }
    }

    func test_rejectsNonHexKey() {
        // 64 chars but contains 'z' — not hex.
        let badKey = String(repeating: "z", count: 64)
        let uri = "olcrtc://wbstream?datachannel@room-01#\(badKey)"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            guard case .invalidKeyHex? = error as? OlcRTCURIParser.ParseError else {
                return XCTFail("Expected invalidKeyHex, got \(error)")
            }
        }
    }

    func test_rejectsUnsupportedProvider_explicit() {
        let uri = "olcrtc://zoom?datachannel@room-01#\(validKey64)"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            guard case .unknownProvider(let name)? = error as? OlcRTCURIParser.ParseError else {
                return XCTFail("Expected unknownProvider, got \(error)")
            }
            XCTAssertEqual(name, "zoom")
        }
    }

    func test_rejectsUnsupportedTransport_explicit() {
        let uri = "olcrtc://wbstream?webrtc@room-01#\(validKey64)"
        XCTAssertThrowsError(try parser.parse(uri)) { error in
            guard case .unknownTransport(let name)? = error as? OlcRTCURIParser.ParseError else {
                return XCTFail("Expected unknownTransport, got \(error)")
            }
            XCTAssertEqual(name, "webrtc")
        }
    }

    func test_jitsiURLRoomID_withQueryAndHashKey() throws {
        // jitsi URL room: contains scheme, slashes, and a `?roomID=` — must
        // still split on the last `#` for the key.
        let uri = "olcrtc://jitsi?datachannel@https://meet1.arbitr.ru/room?id=42#\(validKey64)$LiveRoom"
        let parsed = try parser.parse(uri)
        XCTAssertEqual(parsed.roomID, "https://meet1.arbitr.ru/room?id=42")
        XCTAssertEqual(parsed.keyHex, validKey64)
    }

    func test_normalizesUppercaseHexKeyToLowercase() throws {
        let uri = "olcrtc://wbstream?datachannel@room-01#\(validKey64.uppercased())"
        let parsed = try parser.parse(uri)
        XCTAssertEqual(parsed.keyHex, validKey64)
    }
}
