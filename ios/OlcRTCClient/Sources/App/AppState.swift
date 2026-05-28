import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var mode: ConnectionMode = .vpn
    @Published var status: TunnelStatus = .disconnected

    @Published var provider: OlcRTCProvider = .jitsi
    @Published var transport: OlcRTCTransport = .datachannel
    @Published var roomID: String = ""
    @Published var clientID: String = ""
    @Published var keyHex: String = ""

    @Published var socksHost: String = "127.0.0.1"
    @Published var socksPort: String = "8808"
    @Published var dnsServer: String = "8.8.8.8:53"
    @Published var debug: Bool = false

    @Published var profiles: [OlcRTCProfile] = []
    @Published var logLines: [String] = LogsView.placeholderLogs()
    @Published var lastError: String?

    private let store = ProfileStore.shared
    private let sanitizer = LogSanitizer()
    #if !canImport(OlcRTCMobile)
    private let mock = MockOlcRTCService()
    #endif

    private(set) lazy var vpnManager = VPNManager()
    #if canImport(OlcRTCMobile)
    private(set) lazy var localProxy = LocalProxyManager(logSink: { [weak self] line in
        self?.appendLog(line)
    })
    #else
    private(set) lazy var localProxy = LocalProxyManager(service: mock)
    #endif

    init() {
        profiles = store.load()
    }

    func currentProfile() -> OlcRTCProfile {
        OlcRTCProfile(
            name: "ad-hoc",
            provider: provider,
            transport: transport,
            roomID: roomID,
            clientID: clientID,
            keyHex: keyHex,
            socksHost: socksHost,
            socksPort: Int(socksPort) ?? 8808,
            dnsServer: dnsServer,
            debug: debug
        )
    }

    func start() async {
        lastError = nil
        status = .starting
        appendLog("Starting in \(mode.displayName)…")
        do {
            switch mode {
            case .vpn:
                try await vpnManager.start(profile: currentProfile())
                status = .running(endpoint: nil)
                appendLog("VPN Mode requested. Note: real device runtime requires signing + provisioning + NetworkExtension entitlement.")
            case .localProxy:
                let endpoint = try await localProxy.start(profile: currentProfile())
                status = .running(endpoint: endpoint)
                appendLog("Local Proxy started at \(endpoint). Foreground only; iOS may suspend in background.")
            }
        } catch {
            status = .failed(reason: error.localizedDescription)
            lastError = error.localizedDescription
            appendLog("Start failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        status = .stopping
        appendLog("Stopping…")
        switch mode {
        case .vpn:
            await vpnManager.stop()
        case .localProxy:
            await localProxy.stop()
        }
        status = .disconnected
        appendLog("Stopped.")
    }

    func check() {
        appendLog("Check: profile fields validation is a stub in this scaffold.")
        if roomID.isEmpty { lastError = "Room ID is empty" }
        else if keyHex.isEmpty { lastError = "Encryption key is empty" }
        else { lastError = nil; appendLog("Check OK (stub).") }
    }

    func ping() async {
        #if canImport(OlcRTCMobile)
        // Real Ping is wired in `RealOlcRTCService.ping(...)` via
        // `LocalProxyManager.ping(...)`. The UI does not yet drive that
        // call directly; surface a deliberate stub message instead of a
        // fake mock latency when the real framework is linked.
        appendLog("Ping: real gomobile Ping is wired in RealOlcRTCService; UI hookup is intentionally pending.")
        #else
        appendLog("Ping: not yet wired to gomobile. Stub returns mock latency.")
        let ms = await mock.mockPingMillis()
        appendLog("Ping (mock): \(ms) ms")
        #endif
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "olcrtc" else { return }
        do {
            let parsed = try OlcRTCURIParser().parse(url.absoluteString)
            let profile = parsed.toProfile(name: "Imported")
            profiles.append(profile)
            try? store.save(profiles)
            appendLog("Imported profile from olcrtc:// URI (key masked).")
        } catch {
            appendLog("URI import failed: \(error.localizedDescription)")
        }
    }

    func appendLog(_ raw: String) {
        let line = sanitizer.sanitize(raw)
        let ts = ISO8601DateFormatter().string(from: Date())
        logLines.append("[\(ts)] \(line)")
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    func clearLogs() {
        logLines.removeAll()
    }
}
