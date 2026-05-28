import Foundation
import NetworkExtension

/// Owns the system VPN configuration for VPN Mode.
///
/// At this scaffold stage the manager only **records intent** — it does
/// not actually install or start a tunnel, because:
///
/// - the project is built unsigned (see ADR-0008), so iOS rejects
///   `NETunnelProviderManager` saves on a real device;
/// - the `PacketTunnelProvider` extension itself is a stub.
///
/// The public API is shaped the way the real implementation will look,
/// so wiring up the real `NETunnelProviderManager.loadAllFromPreferences`
/// + `saveToPreferences` + `startVPNTunnel` flow later is a drop-in
/// replacement.
///
/// TODO(gomobile): once `OlcRTCMobile.xcframework` is linked into the
/// extension, the manager will pass the selected profile via
/// `NETunnelProviderProtocol.providerConfiguration` and the extension
/// will read it to drive the Go runtime.
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

    /// Records the desired VPN configuration. Does **not** start a real
    /// tunnel today.
    func start(profile: OlcRTCProfile) async throws {
        _ = profile
        // Intentionally a stub — see file header.
        throw VPNManagerError.notWiredYet
    }

    func stop() async {
        // No-op until VPNManager actually owns an NETunnelProviderSession.
    }
}
