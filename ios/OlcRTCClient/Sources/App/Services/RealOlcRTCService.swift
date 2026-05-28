import Foundation

#if canImport(OlcRTCMobile)
import OlcRTCMobile

/// Real olcRTC service backed by the gomobile-generated `OlcRTCMobile.xcframework`.
/// Only compiled when the framework is available (i.e., after `scripts/build-gomobile-ios.sh`
/// has run and the framework is present at `ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework`).
///
/// See `docs/ai/GOMOBILE_BINDINGS.md` for the authoritative symbol mapping.
class RealOlcRTCService {
    private let logSink: (String) -> Void
    private var logWriter: SwiftLogWriter?

    init(logSink: @escaping (String) -> Void) {
        self.logSink = logSink
    }

    func start(
        carrier: String,
        transport: String,
        roomID: String,
        clientID: String,
        keyHex: String,
        socksPort: Int,
        socksHost: String,
        dnsServer: String,
        vp8FPS: Int,
        vp8BatchSize: Int,
        livenessIntervalMillis: Int,
        livenessTimeoutMillis: Int,
        livenessFailures: Int,
        debug: Bool
    ) throws {
        // Configure before start.
        MobileSetProviders()
        MobileSetTransport(transport)
        MobileSetDNS(dnsServer)
        MobileSetSocksListenHost(socksHost)
        MobileSetVP8Options(vp8FPS, vp8BatchSize)
        MobileSetLivenessOptions(livenessIntervalMillis, livenessTimeoutMillis, livenessFailures)
        MobileSetDebug(debug)

        // Wire log writer if not already set.
        if logWriter == nil {
            let writer = SwiftLogWriter(logSink: logSink)
            logWriter = writer
            MobileSetLogWriter(writer)
        }

        // Start with explicit transport.
        // Go signature: StartWithTransport(carrierName, transportName, roomID, clientID, keyHex string, socksPort int, socksUser, socksPass string) error
        // Obj-C: BOOL MobileStartWithTransport(NSString* carrierName, NSString* transportName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, NSString* socksUser, NSString* socksPass, NSError** error)
        // Swift: try MobileStartWithTransport(_:_:_:_:_:_:_:_:)
        try MobileStartWithTransport(
            carrier,
            transport,
            roomID,
            clientID,
            keyHex,
            socksPort,
            "", // socksUser (empty = no auth)
            ""  // socksPass
        )
    }

    func stop() {
        MobileStop()
    }

    func isRunning() -> Bool {
        return MobileIsRunning()
    }

    func check(
        carrier: String,
        transport: String,
        roomID: String,
        clientID: String,
        keyHex: String,
        socksPort: Int,
        timeoutMillis: Int,
        vp8FPS: Int,
        vp8BatchSize: Int
    ) throws -> Int64 {
        // Go signature: Check(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis, vp8FPS, vp8BatchSize int) (int64, error)
        // Obj-C: BOOL MobileCheck(..., int64_t* ret0_, NSError** error)
        // Swift: try MobileCheck(_:_:_:_:_:_:_:_:_:_:) -> Int64
        return try MobileCheck(
            carrier,
            transport,
            roomID,
            clientID,
            keyHex,
            socksPort,
            timeoutMillis,
            vp8FPS,
            vp8BatchSize
        )
    }

    func ping(
        carrier: String,
        transport: String,
        roomID: String,
        clientID: String,
        keyHex: String,
        socksPort: Int,
        timeoutMillis: Int,
        pingURL: String,
        vp8FPS: Int,
        vp8BatchSize: Int
    ) throws -> Int64 {
        // Go signature: Ping(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis int, pingURL string, vp8FPS, vp8BatchSize int) (int64, error)
        // Swift: try MobilePing(_:_:_:_:_:_:_:_:_:_:_:) -> Int64
        return try MobilePing(
            carrier,
            transport,
            roomID,
            clientID,
            keyHex,
            socksPort,
            timeoutMillis,
            pingURL,
            vp8FPS,
            vp8BatchSize
        )
    }

    func waitReady(timeoutMillis: Int) throws {
        try MobileWaitReady(timeoutMillis)
    }
}

/// Swift implementation of the `MobileLogWriter` protocol.
/// Routes log lines through the sanitizer before forwarding to the app log sink.
private class SwiftLogWriter: NSObject, MobileLogWriter {
    private let logSink: (String) -> Void

    init(logSink: @escaping (String) -> Void) {
        self.logSink = logSink
        super.init()
    }

    func writeLog(_ msg: String?) {
        guard let msg = msg, !msg.isEmpty else { return }
        // Sanitize before forwarding (per ADR-0010).
        let sanitized = LogSanitizer.sanitize(msg)
        logSink(sanitized)
    }
}

#endif
