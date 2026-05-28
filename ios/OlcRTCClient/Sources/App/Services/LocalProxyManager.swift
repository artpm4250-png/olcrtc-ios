import Foundation

/// Drives Local Proxy Mode — the foreground SOCKS endpoint.
///
/// At this scaffold stage it talks to `MockOlcRTCService` instead of
/// the real Go core. Once `OlcRTCMobile.xcframework` is linked, this
/// will call into the gomobile-exported `Start` / `Stop` /
/// `SetSocksListenHost` / `SetLogWriter` functions instead.
///
/// TODO(gomobile): replace `MockOlcRTCService` with a real bridge to
/// `OlcRTCMobileStart(...)` / `OlcRTCMobileStop()`. The SOCKS endpoint
/// returned here is what the Connect screen displays.
@MainActor
final class LocalProxyManager {
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
}
