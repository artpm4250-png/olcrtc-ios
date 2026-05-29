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
/// - As of probe v9 on the `packet-tunnel-gomobile-probe` branch,
///   `startTunnel` calls `GomobileExtensionProbe.touchNonStartingAPI()`
///   immediately before returning `notWiredYet`. That call references
///   `MobileSetDebug(false)` and `MobileIsRunning()` — configure /
///   read-only symbols, no network work. The point of probe v9 is to
///   make the link edge to `OlcRTCMobile.xcframework` reachable from a
///   real runtime entrypoint (the principal class's `startTunnel`),
///   not from an artificial anchor that earlier probes (v5–v8) showed
///   ld_prime is willing to strip.
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

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("startTunnel called on stub provider", log: log, type: .info)

        #if canImport(OlcRTCMobile)
        // Probe v9 (branch `packet-tunnel-gomobile-probe`, Milestone 3
        // in `docs/ROADMAP.md`). Probes v5–v8 anchored the gomobile
        // reference in artificial constructs (linker-forced anchors,
        // `__attribute__((constructor))` functions, stored properties
        // initialized at instance init). Every one of those was
        // stripped by ld_prime's regular dead-strip on Xcode 16.4 /
        // iOS 18.5 SDK — final `otool -L` never showed
        // `OlcRTCMobile.framework`, despite the intermediate `.o`
        // files carrying `U _MobileIsRunning` and `U _MobileSetDebug`.
        //
        // v9 makes the reference runtime-observable from the real
        // entrypoint: the extension's principal class's `startTunnel`
        // override, which ld cannot strip without breaking the
        // extension's `NSExtensionPrincipalClass` contract. The call
        // remains safe — `touchNonStartingAPI()` invokes only
        // `MobileSetDebug(false)` (configure-only) and
        // `MobileIsRunning()` (read-only). It does NOT call
        // `MobileStart`, `MobileStartWithTransport`, `MobileCheck`,
        // or `MobilePing`. It does NOT open sockets, configure
        // `NEPacketTunnelNetworkSettings`, or touch
        // `NEPacketTunnelFlow`. The existing fail-fast
        // `notWiredYet` return immediately after still applies — real
        // packet routing remains gated on Milestone 4.
        let gomobileRunning = GomobileExtensionProbe.touchNonStartingAPI()
        NSLog(
            "PacketTunnelProvider gomobile probe: MobileIsRunning=%{public}@",
            gomobileRunning ? "true" : "false"
        )
        #endif

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
