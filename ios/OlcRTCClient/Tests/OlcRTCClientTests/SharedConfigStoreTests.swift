import XCTest

/// Exercises `SharedConfigStore` through its test-friendly
/// `init(fileURL:)` constructor so the round-trip is observable
/// without an App Group entitlement (which the unsigned CI test
/// runner cannot grant). Each test pins the store to a fresh URL
/// under `FileManager.default.temporaryDirectory` and cleans up
/// in `tearDown`.
final class SharedConfigStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedConfigStoreTests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        fileURL = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func sampleConfig(roomID: String = "room-01") -> PacketTunnelConfig {
        PacketTunnelConfig(
            provider: "jitsi",
            transport: "datachannel",
            roomID: roomID,
            clientID: "alice",
            keyHex: "d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799",
            socksHost: "127.0.0.1",
            socksPort: 8808,
            dnsServer: "8.8.8.8:53",
            debug: false,
            vp8FPS: 24,
            vp8BatchSize: 1024
        )
    }

    // MARK: - Tests

    func test_loadReturnsNil_whenFileMissing() {
        let store = SharedConfigStore(fileURL: fileURL)
        XCTAssertNil(store.load())
    }

    func test_saveThenLoad_roundTripsAllFields() throws {
        let store = SharedConfigStore(fileURL: fileURL)
        let original = sampleConfig()
        try store.save(original)
        let loaded = store.load()
        XCTAssertEqual(loaded, original)
    }

    func test_saveOverwrites_previousValue() throws {
        let store = SharedConfigStore(fileURL: fileURL)
        try store.save(sampleConfig(roomID: "first"))
        try store.save(sampleConfig(roomID: "second"))
        XCTAssertEqual(store.load()?.roomID, "second")
    }

    func test_clearRemovesFile_andLoadReturnsNil() throws {
        let store = SharedConfigStore(fileURL: fileURL)
        try store.save(sampleConfig())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(store.clear())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(store.load())
    }

    func test_clearReturnsFalse_whenFileMissing() {
        let store = SharedConfigStore(fileURL: fileURL)
        XCTAssertFalse(store.clear())
    }

    func test_saveUsesSortedKeys_forDeterministicDiffs() throws {
        let store = SharedConfigStore(fileURL: fileURL)
        try store.save(sampleConfig())
        let data = try Data(contentsOf: fileURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        // `clientID` < `debug` < `dnsServer` alphabetically — verify
        // they appear in that order in the serialized output.
        let cidx = text.range(of: "\"clientID\"")?.lowerBound
        let didx = text.range(of: "\"debug\"")?.lowerBound
        let dnsidx = text.range(of: "\"dnsServer\"")?.lowerBound
        XCTAssertNotNil(cidx); XCTAssertNotNil(didx); XCTAssertNotNil(dnsidx)
        if let c = cidx, let d = didx, let dns = dnsidx {
            XCTAssertLessThan(c, d)
            XCTAssertLessThan(d, dns)
        }
    }

    func test_loadReturnsNil_andDoesNotThrow_onMalformedJSON() throws {
        let store = SharedConfigStore(fileURL: fileURL)
        try Data("{this is not json".utf8).write(to: fileURL, options: [.atomic])
        XCTAssertNil(store.load())
    }
}
