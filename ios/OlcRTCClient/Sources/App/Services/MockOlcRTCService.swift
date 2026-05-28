import Foundation

/// Stand-in for the future gomobile bridge to the Go core.
///
/// The real bridge will call into `OlcRTCMobile.xcframework`
/// (`OlcRTCMobileStart`, `OlcRTCMobileStop`, `OlcRTCMobilePing`,
/// `OlcRTCMobileSetLogWriter`, ...). This mock implements just enough
/// shape so the UI can be exercised without the framework.
///
/// TODO(gomobile): delete this file once the real bridge lands and the
/// callers (`LocalProxyManager`, `AppState.ping`) point at it directly.
actor MockOlcRTCService {
    private var running = false

    func start(profile: OlcRTCProfile) async throws {
        if running { return }
        try await Task.sleep(nanoseconds: 200_000_000)
        running = true
    }

    func stop() async {
        running = false
    }

    func mockPingMillis() async -> Int {
        try? await Task.sleep(nanoseconds: 150_000_000)
        return Int.random(in: 40...180)
    }
}
