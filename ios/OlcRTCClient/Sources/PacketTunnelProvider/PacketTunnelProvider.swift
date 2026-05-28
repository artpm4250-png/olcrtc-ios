import Foundation
import NetworkExtension
import os.log

/// Compile-time stub `PacketTunnelProvider` for VPN Mode.
///
/// This is a **real extension target**, not a fake one — the
/// NSExtensionPrincipalClass in Info.plist points here, the
/// entitlements file is in place, and the symbols resolve. But the
/// runtime does **not** pretend the tunnel is working:
///
/// - `startTunnel` immediately fails with `notWiredYet`.
/// - There is no `NEPacketTunnelFlow` plumbing yet.
/// - As of the `packet-tunnel-gomobile-probe` branch the extension
///   does **link** against `OlcRTCMobile.xcframework`, but only via
///   `GomobileExtensionProbe.touch()` (configure / read-only
///   symbols, no network work). The Go runtime is not driven from
///   here.
///
/// TODO(gomobile): once Milestone 3 of `docs/ROADMAP.md` finishes
/// the runtime side, this class will:
///   1. read `PacketTunnelConfig` from the
///      `NETunnelProviderProtocol.providerConfiguration`,
///   2. configure `NEPacketTunnelNetworkSettings`,
///      call `setTunnelNetworkSettings(...)`,
///   3. spin up the Go runtime via the gomobile-bound `Start...`
///      function pointed at a SOCKS endpoint internal to the
///      extension,
///   4. pump packets between `packetFlow` and the Go runtime.
///
/// Whether the same `xcframework` slice can be embedded into both the
/// app and the extension must be verified in a real CI build —
/// extensions run with `APPLICATION_EXTENSION_API_ONLY = YES`, which
/// may flag some symbols.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    enum StubError: LocalizedError {
        case notWiredYet

        var errorDescription: String? {
            "PacketTunnelProvider is a compile-time stub in this build. See docs/ai/DECISIONS.md (ADR-0004, ADR-0006, ADR-0008)."
        }
    }

    private let log = OSLog(
        subsystem: "org.openlibrecommunity.olcrtc.client.PacketTunnelProvider",
        category: "tunnel"
    )

    #if canImport(OlcRTCMobile)
    /// Compile/link probe anchor — branch
    /// `packet-tunnel-gomobile-probe`, Milestone 3 in
    /// `docs/ROADMAP.md`. Initializing this stored property at
    /// instance init time forces the linker to keep the OlcRTCMobile
    /// symbol references inside the extension binary, which is what
    /// proves the extension's compile **and link** path can resolve
    /// against `OlcRTCMobile.xcframework` under
    /// `APPLICATION_EXTENSION_API_ONLY = YES`. Without a reachable
    /// reference like this, Swift dead-code-stripping discards the
    /// probe and the link edge is silently absent.
    ///
    /// `GomobileExtensionProbe.touch()` runs ONLY
    /// `MobileSetDebug(false)` and `MobileIsRunning()` — both are
    /// configure / read-only, neither starts any network work. The
    /// probe does NOT call `MobileStart` / `MobileStartWithTransport`
    /// / `MobileCheck` / `MobilePing`, does NOT open sockets, and
    /// does NOT change the behavior of `startTunnel` below
    /// (which still fails fast with `notWiredYet`).
    private let _gomobileLinkAnchor: Bool = GomobileExtensionProbe.touch()
    #endif

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("startTunnel called on stub provider", log: log, type: .info)
        completionHandler(StubError.notWiredYet)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        os_log("stopTunnel called on stub provider (reason: %{public}d)",
               log: log, type: .info, reason.rawValue)
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        completionHandler?(nil)
    }
}
