import Foundation
import NetworkExtension
import os.log

/// Owns the system VPN configuration for VPN Mode.
///
/// At this scaffold stage the manager only **records intent** — it does
/// not actually install or start a tunnel, because:
///
/// - the project is built unsigned (see ADR-0008), so iOS rejects
///   `NETunnelProviderManager` saves on a real device;
/// - the `PacketTunnelProvider` extension hosts a Milestone 3.5
///   lifecycle skeleton that still returns `notWiredYet`.
///
/// The public API is shaped the way the real implementation will look,
/// so wiring up the real `NETunnelProviderManager.loadAllFromPreferences`
/// + `saveToPreferences` + `startVPNTunnel` flow later is a drop-in
/// replacement.
///
/// **Milestone 3.5 addition.** Before throwing `notWiredYet`, the
/// manager now persists the selected profile's `PacketTunnelConfig`
/// into the App Group `SharedConfigStore` (ADR-0010 + ROADMAP
/// Milestone 3.5). This exercises the shared schema end-to-end:
/// when signing eventually lands and the real VPN flow runs, the
/// extension's fallback path in `SharedConfigStore.load()` already
/// has data to read. Under the unsigned CI path the save throws
/// `containerUnavailable` (no entitlement is granted), which is
/// caught and surfaced as a sanitized log line — no failure
/// propagates to the caller.
@MainActor
final class VPNManager {
    enum VPNManagerError: LocalizedError {
        case notWiredYet

        var errorDescription: String? {
            switch self {
            case .notWiredYet:
                return "VPN Mode is architected but not wired to a real tunnel in this build. See About → VPN Mode."
            }
        }
    }

    private let sharedConfig = SharedConfigStore()
    private let log = OSLog(
        subsystem: "org.openlibrecommunity.olcrtc.client",
        category: "vpn-manager"
    )

    /// Records the desired VPN configuration. Persists the resolved
    /// `PacketTunnelConfig` into the App Group shared container as a
    /// side effect, then throws `notWiredYet` because real VPN
    /// runtime is Milestone 4 work.
    func start(profile: OlcRTCProfile) async throws {
        let config = PacketTunnelConfig(profile: profile)
        do {
            try sharedConfig.save(config)
            os_log("VPNManager.start: persisted PacketTunnelConfig to shared container",
                   log: log, type: .info)
        } catch SharedConfigStore.Error.containerUnavailable {
            // Expected under the unsigned CI build path. Not a
            // user-facing failure; the architecture stays correct
            // for the signed path.
            os_log("VPNManager.start: shared container unavailable (unsigned build) — config not persisted",
                   log: log, type: .info)
        } catch {
            // Encode / write failures are unexpected but non-fatal
            // for the stub flow. Surface in os_log; let the throw
            // below carry the user-facing reason.
            os_log("VPNManager.start: persist failed: %{public}@",
                   log: log, type: .error, String(describing: error))
        }
        throw VPNManagerError.notWiredYet
    }

    func stop() async {
        // No-op until VPNManager actually owns an NETunnelProviderSession.
        // The shared config is intentionally NOT cleared on stop — the
        // selected profile survives across stop/start cycles. A future
        // explicit "forget profile" UI action would call
        // `SharedConfigStore.clear()`.
    }
}
