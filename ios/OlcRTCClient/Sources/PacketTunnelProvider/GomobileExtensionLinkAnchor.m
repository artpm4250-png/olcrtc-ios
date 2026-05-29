// GomobileExtensionLinkAnchor.m
//
// Compile/link probe (branch `packet-tunnel-gomobile-probe`,
// Milestone 3 in `docs/ROADMAP.md`) — Objective-C / C anchor that
// keeps the extension binary's link edge to
// `OlcRTCMobile.xcframework` alive through Swift whole-module
// optimization and ld_prime's `-dead_strip`.
//
// **Why this file is in C, not Swift.** Probe v2-v4 used a Swift
// stored property
// (`PacketTunnelProvider._gomobileLinkAnchor: Bool =
// GomobileExtensionProbe.touch()`) to reference `MobileIsRunning`
// and `MobileSetDebug`. With `-O -whole-module-optimization` the
// Swift optimizer proved nothing read that `private let`, elided
// the storage *and* its initializer, and the gomobile symbol
// references vanished from the extension's object code before the
// linker ran. Linker-side flags (`-u`, `-needed_framework`) cannot
// rescue references that never reach the linker — see the
// `2026-05-29 — Probe v4 result` entry in `docs/ai/TASK_LOG.md`.
//
// The C anchor below is opaque to Swift WMO: clang compiles it
// independently, `__attribute__((used))` stops clang from removing
// it as unused, and the matching `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor`
// in the extension target's `OTHER_LDFLAGS` (see
// `ios/OlcRTCClient/project.yml`) tells ld to keep the symbol in
// the final binary. The function body then carries genuine
// undefined references to `_MobileIsRunning` and `_MobileSetDebug`,
// which forces ld to keep `LC_LOAD_DYLIB` for `OlcRTCMobile` and
// makes those undefs visible in `nm -u`.
//
// **What this file does NOT do.**
// - It does not start the olcRTC runtime. `MobileStart`,
//   `MobileStartWithTransport`, `MobileCheck`, and `MobilePing`
//   are never called.
// - It does not open sockets, configure
//   `NEPacketTunnelNetworkSettings`, or touch
//   `NEPacketTunnelFlow`.
// - It is never invoked from `PacketTunnelProvider.startTunnel`
//   — `startTunnel` still fails fast with `notWiredYet`.
// - The two calls below are the safest pair the gomobile surface
//   exposes: `MobileIsRunning()` is a pure status read,
//   `MobileSetDebug(NO)` is a configure-only flag flip. Neither
//   touches the network or any I/O.

#import <Foundation/Foundation.h>
#import <OlcRTCMobile/OlcRTCMobile.h>

__attribute__((used))
void OlcRTCExtensionGomobileLinkAnchor(void) {
    (void)MobileIsRunning();
    MobileSetDebug(NO);
}
