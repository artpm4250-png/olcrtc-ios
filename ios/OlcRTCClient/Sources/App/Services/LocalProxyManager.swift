import Foundation

/// Drives Local Proxy Mode — the foreground SOCKS endpoint.
///
/// When `OlcRTCMobile.xcframework` is available (i.e., after
/// `scripts/build-gomobile-ios.sh` has run), this uses `RealOlcRTCService`
/// to call the gomobile-exported API. Otherwise it falls back to
/// `MockOlcRTCService` for scaffold-only builds.
@MainActor
final class LocalProxyManager {
    #if canImport(OlcRTCMobile)
    private let realService: RealOlcRTCService
    private let logSink: (String) -> Void

    init(logSink: @escaping (String) -> Void) {
        self.logSink = logSink
        self.realService = RealOlcRTCService(logSink: logSink)
    }

    /// Returns the endpoint string (e.g. "127.0.0.1:8808") on success.
    func start(profile: OlcRTCProfile) async throws -> String {
        try realService.start(
            carrier: profile.provider.rawValue,
            transport: profile.transport.rawValue,
            roomID: profile.roomID,
            clientID: profile.clientID,
            keyHex: profile.keyHex,
            socksPort: profile.socksPort,
            socksHost: profile.socksHost,
            dnsServer: profile.dnsServer,
            vp8FPS: profile.vp8FPS,
            vp8BatchSize: profile.vp8BatchSize,
            livenessIntervalMillis: profile.livenessIntervalMillis,
            livenessTimeoutMillis: profile.livenessTimeoutMillis,
            livenessFailures: profile.livenessFailures,
            debug: profile.debug
        )
        return "\(profile.socksHost):\(profile.socksPort)"
    }

    func stop() async {
        realService.stop()
    }

    func isRunning() -> Bool {
        return realService.isRunning()
    }

    func check(profile: OlcRTCProfile, timeoutMillis: Int) async throws -> Int64 {
        return try realService.check(
            carrier: profile.provider.rawValue,
            transport: profile.transport.rawValue,
            roomID: profile.roomID,
            clientID: profile.clientID,
            keyHex: profile.keyHex,
            socksPort: profile.socksPort,
            timeoutMillis: timeoutMillis,
            vp8FPS: profile.vp8FPS,
            vp8BatchSize: profile.vp8BatchSize
        )
    }

    func ping(profile: OlcRTCProfile, timeoutMillis: Int, pingURL: String) async throws -> Int64 {
        return try realService.ping(
            carrier: profile.provider.rawValue,
            transport: profile.transport.rawValue,
            roomID: profile.roomID,
            clientID: profile.clientID,
            keyHex: profile.keyHex,
            socksPort: profile.socksPort,
            timeoutMillis: timeoutMillis,
            pingURL: pingURL,
            vp8FPS: profile.vp8FPS,
            vp8BatchSize: profile.vp8BatchSize
        )
    }

    #else
    // Fallback to mock when OlcRTCMobile is not available.
    private let service: MockOlcRTCService

    init(service: MockOlcRTCService) {
        self.service = service
    }

    /// Returns the endpoint string (e.g. "127.0.0.1:8808") on success.
    func start(profile: OlcRTCProfile) async throws -> String {
        try await service.start(profile: profile)
        return "\(profile.socksHost):\(profile.socksPort)"
    }

    func stop() async {
        await service.stop()
    }

    func isRunning() -> Bool {
        return false
    }

    func check(profile: OlcRTCProfile, timeoutMillis: Int) async throws -> Int64 {
        return 0
    }

    func ping(profile: OlcRTCProfile, timeoutMillis: Int, pingURL: String) async throws -> Int64 {
        return 0
    }
    #endif
}
