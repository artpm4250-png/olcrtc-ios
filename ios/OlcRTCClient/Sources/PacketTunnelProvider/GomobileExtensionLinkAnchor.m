// GomobileExtensionLinkAnchor.m
//
// Compile/link probe (branch `packet-tunnel-gomobile-probe`,
// Milestone 3 in `docs/ROADMAP.md`) — Objective-C / C anchor that
// keeps the extension binary's link edge to
// `OlcRTCMobile.xcframework` alive across Swift WMO, ld_prime's
// `-dead_strip`, ld_prime's unused-dylib pruning, **and** any
// future LTO-pass that prefers to fold call sites with discarded
// results.
//
// **History (full chain in `docs/ai/TASK_LOG.md`).**
// - v2 used a Swift `private let` calling
//   `MobileIsRunning` — Swift WMO eliminated it before the
//   linker ran.
// - v3 added `-Wl,-u,_MobileIsRunning` — ld dead-stripped the
//   framework anyway.
// - v4 added `-Wl,-needed_framework,OlcRTCMobile` — ld_prime
//   allowed the trailing `-framework OlcRTCMobile` to shadow
//   the `needed` flag.
// - v5 moved the anchor to a C function with
//   `__attribute__((used))` — the symbol survived but LTO + -Os
//   folded its body.
// - v6 made the anchor's gomobile references data relocations
//   via static function-pointer initializers plus `volatile` +
//   `optnone` — the .o files had `U _MobileIsRunning` and
//   `U _MobileSetDebug`, but ld_prime still nullified the
//   relocations.
// - v7 set `LLVM_LTO = NO` on the extension target. The full
//   xcodebuild log of the v7 run confirmed clang per-TU compile
//   carried no `-flto=…`, i.e. LTO was actually off at compile
//   time. The link edge still died — proving the culprit is
//   ld_prime's regular dead-strip / unused-dylib pruning, not
//   LTO. `__attribute__((used))` keeps the storage of static
//   variables, but not the **data relocations** that fill those
//   storage slots from external symbols, when ld decides
//   nothing live references those symbols.
//
// **What v8 changes.** A `__attribute__((constructor))` function
// is added next to the existing linker-forced anchor. dyld
// scans `__DATA,__mod_init_func` at module load and calls every
// constructor — those calls are roots of the binary's
// reachability graph, exactly the way `_main` /
// `_NSExtensionMain` is. ld cannot dead-strip a constructor
// without breaking module initialization, so the constructor's
// body — including its direct calls to `MobileIsRunning` and
// `MobileSetDebug` — must survive into the final binary as
// real call instructions, which in turn force the linker to
// keep `LC_LOAD_DYLIB` for `OlcRTCMobile`.
//
// The linker-forced anchor
// (`OlcRTCExtensionGomobileLinkAnchor` + the
// `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor` flag in
// `project.yml`) is intentionally kept alongside the
// constructor. Two independent live paths are better than one:
// if Apple ever changes module-init handling, the linker-forced
// anchor still keeps the symbol; if `-Wl,-u` is ever removed
// from `OTHER_LDFLAGS`, the constructor still keeps the
// references.
//
// **What this file does NOT do.**
// - It does not start the olcRTC runtime. `MobileStart`,
//   `MobileStartWithTransport`, `MobileCheck`, and `MobilePing`
//   are never named here.
// - It does not open sockets, configure
//   `NEPacketTunnelNetworkSettings`, or touch
//   `NEPacketTunnelFlow`.
// - The constructor body and the linker-forced anchor are
//   never invoked from `PacketTunnelProvider.startTunnel` —
//   `startTunnel` still fails fast with `notWiredYet`.
// - `MobileIsRunning` (pure status read, returns `NO` before
//   any `MobileStart*` is called) and `MobileSetDebug`
//   (configure-only flag flip) are the safest pair on the
//   gomobile surface. Both calls happen once at module-init
//   inside the extension process; neither touches the network
//   or any I/O. The extension is **not yet ever loaded** by
//   the system in the unsigned CI build path (no signing →
//   no `NETunnelProviderManager` install), so even the
//   constructor itself does not run in CI today.

#import <Foundation/Foundation.h>
#import <OlcRTCMobile/OlcRTCMobile.h>

// Volatile sink used by both anchors. Marked `used` so the
// optimizer cannot remove the storage, and `volatile` so reads
// and writes are observable behavior under the C standard.
__attribute__((used))
static volatile BOOL OlcRTCGomobileBoolSink = NO;

// v8 constructor anchor. Registered with dyld via
// `__DATA,__mod_init_func`; runs once at module load. ld
// treats this as live regardless of any `-dead_strip` /
// unused-dylib heuristics because dyld dispatches to it.
__attribute__((constructor))
__attribute__((used))
static void OlcRTCExtensionGomobileConstructorAnchor(void) {
    BOOL running = MobileIsRunning();
    OlcRTCGomobileBoolSink = running;
    MobileSetDebug(OlcRTCGomobileBoolSink);
}

// v5/v6 linker-forced anchor. Kept in place so the
// `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor` flag in the
// extension target's `OTHER_LDFLAGS` continues to have a
// definition to anchor on, and so a future toolchain change
// that breaks module-init handling still has the linker-force
// path as a fallback. `optnone` keeps the body's volatile
// loads and indirect calls from being folded.
__attribute__((used, noinline, optnone))
void OlcRTCExtensionGomobileLinkAnchor(void) {
    BOOL running = MobileIsRunning();
    OlcRTCGomobileBoolSink = running;
    MobileSetDebug(OlcRTCGomobileBoolSink);
}
