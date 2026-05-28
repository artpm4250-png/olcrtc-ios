import Foundation

#if canImport(OlcRTCMobile)
import OlcRTCMobile

/// Compile/link probe for the `PacketTunnelProvider` extension target.
///
/// Branch: `packet-tunnel-gomobile-probe`.
/// Tracks Milestone 3 in `docs/ROADMAP.md` (PacketTunnelProvider /
/// gomobile feasibility probe).
///
/// **What this file is.** A deliberately minimal Swift file that
/// imports `OlcRTCMobile` and references two symbols from it. Its only
/// job is to force the extension target's linker to actually resolve
/// against the gomobile-generated `OlcRTCMobile.xcframework` and the
/// underlying Go runtime when the extension is built under
/// `APPLICATION_EXTENSION_API_ONLY = YES`. If the link succeeds, we
/// know the framework is compatible with extension build settings.
/// If it fails, the workflow log tells us exactly which symbol or
/// build setting Apple rejects — that information then drives the
/// follow-up (shim, isolate, or escalate to upstream Go core).
///
/// **What this file is NOT.**
/// - It does **not** start the olcRTC runtime in the extension. There
///   is no `MobileStart`, `MobileStartWithTransport`, `MobileCheck`,
///   or `MobilePing` call here.
/// - It does **not** wire `PacketTunnelProvider.startTunnel` to the Go
///   core. That extension's `startTunnel` still fails fast with
///   `notWiredYet`.
/// - It does **not** open any sockets, configure
///   `NEPacketTunnelNetworkSettings`, or touch
///   `NEPacketTunnelFlow`. None of that is part of this probe.
/// - It does **not** add new features visible to the user.
///
/// Symbols referenced:
///   - `MobileIsRunning()` — pure status read, defined by the Go core
///     as `bool` and bound by gomobile as `MobileIsRunning() -> Bool`.
///     Does not start, stop, or touch any I/O.
///   - `MobileSetDebug(false)` — configure-only, sets a flag in the Go
///     runtime; no network work.
///
/// Both are read-only / configure-only and idempotent. They never run
/// inside `startTunnel` here — they live behind a function the
/// extension's principal class doesn't call. The function gets a
/// `@discardableResult` so the compiler does not strip the body and
/// the linker still pulls in the symbols at link time.
enum GomobileExtensionProbe {
    /// Reference the symbols without invoking any network behavior.
    /// Intentionally not called from `startTunnel` — see the file
    /// header. Marked `@discardableResult` plus a non-Void return so
    /// the compiler keeps the body intact even with whole-module
    /// optimization on.
    @discardableResult
    static func touch() -> Bool {
        // Configure-only flag. Setting it to `false` makes the call a
        // no-op on a clean process state.
        MobileSetDebug(false)
        // Read-only status. Always returns `false` before any
        // `MobileStart*` is called — and we deliberately never call
        // any starter from the extension in this probe.
        return MobileIsRunning()
    }
}

#endif
