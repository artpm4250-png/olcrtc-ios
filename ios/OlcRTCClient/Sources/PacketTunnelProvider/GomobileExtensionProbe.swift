import Foundation

#if canImport(OlcRTCMobile)
import OlcRTCMobile

/// Compile/link anchor for the `PacketTunnelProvider` extension target.
///
/// Branch: `packet-tunnel-runtime-skeleton`. Tracks Milestone 3.5 in
/// `docs/ROADMAP.md` (PacketTunnelProvider runtime skeleton).
/// Architecture locked in by [ADR-0013](../../docs/ai/DECISIONS.md):
/// `OlcRTCMobile.xcframework` is a static framework wrapper, so the
/// extension links it via `-force_load` of the per-sdk slice. This
/// file exists so the Swift compile step has an `import OlcRTCMobile`
/// to satisfy — without it the module would never be resolved into
/// the extension and the link edge would be unobservable in source.
///
/// **What this file is.** A deliberately minimal Swift surface that
/// imports `OlcRTCMobile` and references two configure-only / read-only
/// symbols (`MobileSetDebug`, `MobileIsRunning`). It is the source-side
/// half of the v12 link contract; the linker-side half is the
/// `OTHER_LDFLAGS[sdk=…]*` `-force_load` in `project.yml`.
///
/// **What this file is NOT.**
/// - It does **not** start the olcRTC runtime in the extension. There
///   is no `MobileStart`, `MobileStartWithTransport`, `MobileCheck`,
///   or `MobilePing` call here.
/// - It does **not** open any sockets, configure
///   `NEPacketTunnelNetworkSettings`, or touch `NEPacketTunnelFlow`.
///   None of that is part of Milestone 3.5.
/// - It does **not** add user-visible features.
///
/// Called from `PacketTunnelProvider.startTunnel` so the reference is
/// reachable from the extension's `NSExtensionPrincipalClass` rather
/// than only from a free function ld can dead-strip (probes v2–v9
/// proved free-function / static / constructor anchors all get
/// stripped; the working anchor is a call from the principal class
/// plus `-force_load` at the linker level).
enum GomobileExtensionProbe {
    /// Reference the symbols without invoking any network behavior.
    /// Returns `MobileIsRunning()` so the body is not optimized away;
    /// callers should use the result to gate a sanitized log line and
    /// nothing more.
    @discardableResult
    static func touchNonStartingAPI() -> Bool {
        // Configure-only flag; setting it to `false` is a no-op on a
        // clean process state.
        MobileSetDebug(false)
        // Read-only status. Always returns `false` before any
        // `MobileStart*` is called — and we deliberately never call
        // any starter from the extension in this milestone.
        return MobileIsRunning()
    }
}

#endif
