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
/// - There is no Go runtime loaded — `OlcRTCMobile.xcframework` is not
///   linked into this target yet.
///
/// TODO(gomobile): once `OlcRTCMobile.xcframework` is linked, this
/// class will:
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
