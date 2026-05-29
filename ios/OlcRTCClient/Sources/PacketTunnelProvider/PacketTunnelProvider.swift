import Foundation
import NetworkExtension
import os.log

/// Milestone 3.5 runtime skeleton for VPN Mode's
/// `PacketTunnelProvider` extension.
///
/// Branch: `packet-tunnel-runtime-skeleton`. Architecture locked in by
/// [ADR-0013](../../docs/ai/DECISIONS.md): the gomobile-built
/// `OlcRTCMobile.xcframework` is a static framework wrapper; the
/// extension links its per-sdk slice via `-force_load` in
/// `OTHER_LDFLAGS[sdk=…]*` (see `project.yml`). The Swift module
/// resolves through `import OlcRTCMobile` in
/// `GomobileExtensionProbe.swift`.
///
/// **What this skeleton does.**
///   1. `startTunnel(options:completionHandler:)` decodes a
///      `PacketTunnelConfig` from
///      `NETunnelProviderProtocol.providerConfiguration` (so the
///      shared schema is exercised end-to-end without requiring an
///      App Group / Keychain — those land when signing does);
///   2. sanitized-logs the resolved profile fields through
///      `LogSanitizer` so a future signed-device build cannot leak
///      `keyHex` or `olcrtc://` URIs even by accident;
///   3. exercises the gomobile link edge via
///      `GomobileExtensionProbe.touchNonStartingAPI()` (configure-only
///      `MobileSetDebug` + read-only `MobileIsRunning`) — this is
///      what proves at runtime that the static-linked Go core is
///      actually inside the `.appex` executable;
///   4. returns `StubError.notWiredYet` to the system, honestly
///      reporting that real VPN runtime is gated on Milestone 4.
///
/// `stopTunnel(with:completionHandler:)` is symmetric and idempotent
/// for the skeleton's current state (no Go runtime is started, so
/// there is nothing to tear down beyond logging).
///
/// **What this skeleton deliberately does NOT do.**
///   - No `MobileStart` / `MobileStartWithTransport` / `MobileCheck` /
///     `MobilePing` (Milestone 4).
///   - No sockets, no `NEPacketTunnelNetworkSettings.setTunnelNetworkSettings`,
///     no `NEPacketTunnelFlow` plumbing (Milestone 4).
///   - No App Group access (added when signing is configured;
///     `providerConfiguration` is enough to pass the selected
///     profile across the app/extension boundary today).
///   - No `setTunnelNetworkSettings` callback. The completion handler
///     is invoked with `notWiredYet` instead.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    enum StubError: LocalizedError {
        case notWiredYet
        case missingProviderConfiguration
        case malformedProviderConfiguration

        var errorDescription: String? {
            switch self {
            case .notWiredYet:
                return "PacketTunnelProvider runtime is gated on Milestone 4 (see docs/ai/DECISIONS.md ADR-0008 and docs/ROADMAP.md)."
            case .missingProviderConfiguration:
                return "PacketTunnelProvider was started without an NETunnelProviderProtocol.providerConfiguration."
            case .malformedProviderConfiguration:
                return "PacketTunnelProvider could not decode PacketTunnelConfig from providerConfiguration."
            }
        }
    }

    private let log = OSLog(
        subsystem: "org.openlibrecommunity.olcrtc.client.PacketTunnelProvider",
        category: "tunnel"
    )
    private let sanitizer = LogSanitizer()
    private let sharedConfig = SharedConfigStore()
    private let sharedLog = SharedLogStore()

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        logSanitized("startTunnel: skeleton invoked (Milestone 3.5)", type: .info)

        // 1. Resolve PacketTunnelConfig. Primary source is
        // NETunnelProviderProtocol.providerConfiguration (stamped by
        // the host app's NETunnelProviderManager.saveToPreferences
        // call). Fallback is the App Group SharedConfigStore — useful
        // when the extension is invoked out-of-band (on-demand rule,
        // re-launch, debugging) and the protocol configuration is
        // not populated. Either source is acceptable; both produce
        // the same shared schema.
        let config: PacketTunnelConfig
        if let viaProtocol = decodeProviderConfiguration() {
            logSanitized("startTunnel: config resolved via providerConfiguration", type: .info)
            config = viaProtocol
        } else if let viaShared = sharedConfig.load() {
            logSanitized("startTunnel: config resolved via SharedConfigStore (App Group fallback)", type: .info)
            config = viaShared
        } else {
            logSanitized("startTunnel: no PacketTunnelConfig available (providerConfiguration empty AND SharedConfigStore empty/unavailable)", type: .error)
            completionHandler(StubError.malformedProviderConfiguration)
            return
        }

        // 2. Sanitized-log the resolved profile fields so the
        // app/extension boundary is observable end-to-end without
        // leaking secrets. keyHex is never printed; LogSanitizer
        // also masks the URI form defensively.
        logSanitized(
            "startTunnel: resolved provider=\(config.provider) transport=\(config.transport) room=\(config.roomID) client=\(config.clientID) socks=\(config.socksHost):\(config.socksPort) dns=\(config.dnsServer) debug=\(config.debug)",
            type: .info
        )

        // 3. Exercise the gomobile link edge. This is configure-only
        // (`MobileSetDebug`) + read-only (`MobileIsRunning`) — no
        // network work, no starter call. The point is to prove the
        // static archive is actually inside the .appex binary.
        #if canImport(OlcRTCMobile)
        let running = GomobileExtensionProbe.touchNonStartingAPI()
        logSanitized("startTunnel: gomobile link probe ok (MobileIsRunning=\(running))", type: .info)
        #else
        logSanitized("startTunnel: OlcRTCMobile not available in extension target", type: .error)
        #endif

        // 4. Honestly fail. No tunnel is configured, no packet flow
        // is established. Real VPN runtime lands in Milestone 4.
        logSanitized("startTunnel: returning notWiredYet (Milestone 4 gates real runtime)", type: .info)
        completionHandler(StubError.notWiredYet)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logSanitized("stopTunnel: reason=\(reason.rawValue) (no Go runtime to tear down at Milestone 3.5)", type: .info)
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        completionHandler?(nil)
    }

    // MARK: - Helpers

    /// Decode `PacketTunnelConfig` from the active protocol's
    /// `providerConfiguration` dictionary. Returns `nil` if the
    /// protocol is missing, the configuration is missing, or the
    /// dictionary cannot be re-encoded into the shared schema.
    /// All failure paths emit a sanitized log line first so the
    /// caller can return a typed error directly.
    private func decodeProviderConfiguration() -> PacketTunnelConfig? {
        guard let proto = self.protocolConfiguration as? NETunnelProviderProtocol else {
            logSanitized("startTunnel: protocolConfiguration is not an NETunnelProviderProtocol", type: .error)
            return nil
        }
        guard let raw = proto.providerConfiguration, !raw.isEmpty else {
            logSanitized("startTunnel: providerConfiguration missing or empty", type: .error)
            return nil
        }
        do {
            // PacketTunnelConfig is a Codable struct; bridge through
            // JSON so we tolerate any plist-incompatible types the
            // host app might add (Bool, Int, String, [String: Any]).
            let data = try JSONSerialization.data(withJSONObject: raw, options: [])
            return try JSONDecoder().decode(PacketTunnelConfig.self, from: data)
        } catch {
            logSanitized("startTunnel: failed to decode PacketTunnelConfig: \(error.localizedDescription)", type: .error)
            return nil
        }
    }

    /// Funnel for every extension log line. Runs the line through
    /// `LogSanitizer` (ADR-0010) before handing it to `os_log` AND
    /// mirroring it into the App Group `SharedLogStore` so the host
    /// app's Logs tab can surface extension-side events end-to-end.
    /// `os_log` with `%{public}@` is required so the message survives
    /// to the unified log; the sanitizer is what makes both sinks
    /// safe. `SharedLogStore.append` is a no-op when the App Group
    /// container is unavailable (unsigned CI path).
    private func logSanitized(_ message: String, type: OSLogType) {
        let safe = sanitizer.sanitize(message)
        os_log("%{public}@", log: log, type: type, safe)
        sharedLog.append("[ext] \(safe)")
    }
}
