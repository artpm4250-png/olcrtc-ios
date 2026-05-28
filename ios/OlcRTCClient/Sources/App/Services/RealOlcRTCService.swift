import Foundation

#if canImport(OlcRTCMobile)
import OlcRTCMobile

/// Errors raised when a gomobile call returns `false` but does not
/// supply an `NSError` instance (defensive — should not happen in
/// practice, but Obj-C `BOOL`/`NSError**` patterns allow it).
enum RealOlcRTCServiceError: Error, LocalizedError {
    case startFailed
    case waitReadyFailed
    case checkFailed
    case pingFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:     return "MobileStartWithTransport returned false without an error."
        case .waitReadyFailed: return "MobileWaitReady returned false without an error."
        case .checkFailed:     return "MobileCheck returned false without an error."
        case .pingFailed:      return "MobilePing returned false without an error."
        }
    }
}

/// Real olcRTC service backed by the gomobile-generated `OlcRTCMobile.xcframework`.
/// Only compiled when the framework is available (i.e., after `scripts/build-gomobile-ios.sh`
/// has run and the framework is present at `ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework`).
///
/// The gomobile-generated Obj-C signatures use the classic
/// `BOOL fn(..., NSError** error)` shape. Swift's auto-throws inference
/// does NOT pick these up (the symbol names don't match the heuristics
/// for the Foundation method family), so each call site explicitly:
///
///   1. allocates an `NSError?` and, where applicable, an `Int64` out var,
///   2. passes them by pointer,
///   3. throws the `NSError` (or a fallback) if the call returns `false`,
///   4. otherwise returns the out value.
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

        // Obj-C:
        //   BOOL MobileStartWithTransport(NSString* carrierName, NSString* transportName,
        //                                 NSString* roomID, NSString* clientID, NSString* keyHex,
        //                                 long socksPort, NSString* socksUser, NSString* socksPass,
        //                                 NSError** error);
        var err: NSError?
        let ok = MobileStartWithTransport(
            carrier,
            transport,
            roomID,
            clientID,
            keyHex,
            socksPort,
            "", // socksUser (empty = no auth)
            "", // socksPass
            &err
        )
        if !ok {
            throw err ?? RealOlcRTCServiceError.startFailed
        }
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
        // Obj-C:
        //   BOOL MobileCheck(NSString* carrierName, NSString* transportName,
        //                    NSString* roomID, NSString* clientID, NSString* keyHex,
        //                    long socksPort, long timeoutMillis, long vp8FPS, long vp8BatchSize,
        //                    int64_t* ret0_, NSError** error);
        var ret: Int64 = 0
        var err: NSError?
        let ok = MobileCheck(
            carrier,
            transport,
            roomID,
            clientID,
            keyHex,
            socksPort,
            timeoutMillis,
            vp8FPS,
            vp8BatchSize,
            &ret,
            &err
        )
        if !ok {
            throw err ?? RealOlcRTCServiceError.checkFailed
        }
        return ret
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
        // Obj-C:
        //   BOOL MobilePing(NSString* carrierName, NSString* transportName,
        //                   NSString* roomID, NSString* clientID, NSString* keyHex,
        //                   long socksPort, long timeoutMillis, NSString* pingURL,
        //                   long vp8FPS, long vp8BatchSize, int64_t* ret0_, NSError** error);
        var ret: Int64 = 0
        var err: NSError?
        let ok = MobilePing(
            carrier,
            transport,
            roomID,
            clientID,
            keyHex,
            socksPort,
            timeoutMillis,
            pingURL,
            vp8FPS,
            vp8BatchSize,
            &ret,
            &err
        )
        if !ok {
            throw err ?? RealOlcRTCServiceError.pingFailed
        }
        return ret
    }

    func waitReady(timeoutMillis: Int) throws {
        // Obj-C: BOOL MobileWaitReady(long timeoutMillis, NSError** error);
        var err: NSError?
        let ok = MobileWaitReady(timeoutMillis, &err)
        if !ok {
            throw err ?? RealOlcRTCServiceError.waitReadyFailed
        }
    }
}

/// Swift implementation of the `MobileLogWriter` protocol.
/// Routes log lines through the sanitizer before forwarding to the app log sink.
///
/// `MobileLogWriter` exists in the generated Obj-C as both an
/// `@interface : NSObject` and a same-named `@protocol`, so Swift's
/// importer renames the protocol to `MobileLogWriterProtocol`.
private class SwiftLogWriter: NSObject, MobileLogWriterProtocol {
    private let logSink: (String) -> Void
    private let sanitizer = LogSanitizer()

    init(logSink: @escaping (String) -> Void) {
        self.logSink = logSink
        super.init()
    }

    func writeLog(_ msg: String?) {
        guard let msg = msg, !msg.isEmpty else { return }
        // Sanitize before forwarding (per ADR-0010).
        let sanitized = sanitizer.sanitize(msg)
        logSink(sanitized)
    }
}

#endif
