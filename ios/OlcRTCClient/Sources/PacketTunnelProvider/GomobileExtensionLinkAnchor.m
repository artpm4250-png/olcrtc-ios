// GomobileExtensionLinkAnchor.m
//
// Compile/link probe (branch `packet-tunnel-gomobile-probe`,
// Milestone 3 in `docs/ROADMAP.md`) — Objective-C / C anchor that
// keeps the extension binary's link edge to
// `OlcRTCMobile.xcframework` alive across Swift WMO **and** ld_prime
// LTO + `-dead_strip`.
//
// **Why C, not Swift, and why function pointers, not direct calls.**
// Probe v2-v4: a Swift `private let` calling
// `MobileIsRunning` / `MobileSetDebug` was eliminated by Swift
// `-O -whole-module-optimization` before the linker ever ran, so the
// `Mobile*` symbol references never reached the link step.
// Probe v5: an ObjC/C function with `__attribute__((used))` and a
// matching `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor` made the
// **anchor symbol** survive into the final binary
// (`0000000100004000 T _OlcRTCExtensionGomobileLinkAnchor` in
// `nm`), but Xcode 16.4's default LTO + `-Os` + ARC folded the
// anchor's two-call body into effectively a `ret`: the return value
// of `MobileIsRunning()` was cast to `(void)`, `MobileSetDebug(NO)`
// returns void, neither has any LTO-visible side effect, and both
// calls were dropped as dead. With no surviving call sites the
// extension binary shipped with no `LC_LOAD_DYLIB` for OlcRTCMobile.
// `__attribute__((used))` protects only the **symbol**, not the
// statements inside the body. See
// `docs/ai/TASK_LOG.md` — `2026-05-29 — Probe v5 result`.
//
// Probe v6 puts the gomobile symbol references into Mach-O **data
// relocations**, not call instructions:
//
//   - Two `static volatile` function-pointer variables are
//     initialized with `MobileIsRunning` and `MobileSetDebug`. In
//     C, a function-designator decays to its address; the
//     initializer is a constant expression at compile time but
//     its value is not known until link time, so clang emits a
//     relocation entry against the external symbols
//     `_MobileIsRunning` and `_MobileSetDebug`. Those relocations
//     are not "calls" — LTO has no notion of "the result of this
//     pointer is unused", so it cannot eliminate the entries the
//     way it eliminated the v5 call sites. ld must resolve the
//     relocations against `OlcRTCMobile.framework` regardless of
//     whether anything in the binary ever calls through them, and
//     resolving them forces `LC_LOAD_DYLIB` for the framework to
//     stay.
//   - `__attribute__((used))` on each variable prevents the
//     compiler / LTO from removing the variable itself even if
//     nothing reads it.
//   - `volatile` makes every read and write to the variable an
//     observable side effect under the C standard, so the
//     anchor function below cannot be optimized to a no-op even
//     if its return values are discarded.
//   - The anchor function adds `__attribute__((noinline,
//     optnone))` so its body is compiled with optimization
//     disabled. `optnone` is preserved through to LTO; the
//     anchor's volatile loads, the indirect call, the volatile
//     store, and the second indirect call are all kept.
//
// The combination makes any one of three independent guarantees
// sufficient to keep the link edge:
//   (1) the static-variable relocations alone (data segment),
//   (2) the volatile loads/stores in the anchor body,
//   (3) the anchor symbol forced by `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor`.
// All three would have to fail simultaneously for the extension
// binary to ship without `OlcRTCMobile.framework`.
//
// **What this file does NOT do.**
// - It does not start the olcRTC runtime. `MobileStart`,
//   `MobileStartWithTransport`, `MobileCheck`, and `MobilePing`
//   are never named here.
// - It does not open sockets, configure
//   `NEPacketTunnelNetworkSettings`, or touch
//   `NEPacketTunnelFlow`.
// - `OlcRTCExtensionGomobileLinkAnchor` is never invoked from
//   `PacketTunnelProvider.startTunnel` — `startTunnel` still
//   fails fast with `notWiredYet`. The anchor exists for the
//   linker, not for the runtime; nothing in the live code path
//   depends on its return value or side effects.
// - The two functions referenced — `MobileIsRunning` (pure
//   status read, returns false before any `MobileStart*`) and
//   `MobileSetDebug` (configure-only flag flip) — are the
//   safest pair on the gomobile surface. Even if the anchor
//   ever ran, neither would touch the network or any I/O.

#import <Foundation/Foundation.h>
#import <OlcRTCMobile/OlcRTCMobile.h>

typedef BOOL (*OlcRTCMobileIsRunningFn)(void);
typedef void (*OlcRTCMobileSetDebugFn)(BOOL);

__attribute__((used))
static volatile BOOL OlcRTCGomobileBoolSink = NO;

__attribute__((used))
static volatile OlcRTCMobileIsRunningFn OlcRTCGomobileIsRunningPtr = MobileIsRunning;

__attribute__((used))
static volatile OlcRTCMobileSetDebugFn OlcRTCGomobileSetDebugPtr = MobileSetDebug;

__attribute__((used, noinline, optnone))
void OlcRTCExtensionGomobileLinkAnchor(void) {
    OlcRTCMobileIsRunningFn isRunning =
        (OlcRTCMobileIsRunningFn)OlcRTCGomobileIsRunningPtr;
    OlcRTCMobileSetDebugFn setDebug =
        (OlcRTCMobileSetDebugFn)OlcRTCGomobileSetDebugPtr;

    BOOL running = isRunning();
    OlcRTCGomobileBoolSink = running;
    setDebug(OlcRTCGomobileBoolSink);
}
