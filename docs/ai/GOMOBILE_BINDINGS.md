# GOMOBILE_BINDINGS.md

Curated reference for the Swift / Objective-C surface produced by
`gomobile bind -target=ios ./mobile` against the upstream Go core
(`third_party/olcrtc/mobile`). The Swift integration step
(`LocalProxyManager`, the `PacketTunnelProvider` extension, etc.)
**MUST** use the names recorded here — do not infer them from the Go
source or from training data, because gomobile applies its own
name-mangling rules (package prefix, exported method casing,
error-returning multi-return-value flattening, etc.).

This file is updated **from the actual generated artifacts** of the
`Gomobile iOS Bind` workflow:

- `OlcRTCMobile-xcframework` — the framework itself.
- `gomobile-inspection-report` — `files.txt`, `headers.txt`,
  `modulemaps.txt`, `swiftinterfaces.txt`, `summary.md` produced by
  `scripts/build-gomobile-ios.sh`.

When the artifacts diverge from this document, **the artifacts win**;
update this file in the same commit that wires Swift to a changed
symbol.

---

## 1. Framework + module + import names

Discovered from workflow run
[26588577428](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26588577428)
(commit `b0d635e`).

- **xcframework path (gitignored):**
  `ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework`
- **Framework slices:**
  - `ios-arm64/OlcRTCMobile.framework` (device)
  - `ios-arm64_x86_64-simulator/OlcRTCMobile.framework` (simulator)
- **Module name (for Swift `import`):** `OlcRTCMobile`
- **Module map declares:** `framework module "OlcRTCMobile"`
- **Headers in module:**
  - `ref.h` — gomobile runtime ref-counting support
  - `Universe.objc.h` — gomobile error protocol
  - `Mobile.objc.h` — the actual API surface from `mobile.go`
  - `OlcRTCMobile.h` — umbrella header
- **Bridging header:** not needed; use modular `import OlcRTCMobile`
  directly in Swift.

---

## 2. Generated symbol mapping (Go → Obj-C → Swift)

All Go package-level functions in `mobile.go` surface with a `Mobile`
prefix in Obj-C. Swift imports them with the same `Mobile` prefix
(gomobile does not lowercase the first letter for free functions).

| Go symbol | Obj-C declaration | Swift call | Notes |
|-----------|-------------------|------------|-------|
| `mobile.SetProviders()` | `FOUNDATION_EXPORT void MobileSetProviders(void);` | `MobileSetProviders()` | void |
| `mobile.SetTransport(transport string)` | `FOUNDATION_EXPORT void MobileSetTransport(NSString* _Nullable transport);` | `MobileSetTransport(_:)` | void |
| `mobile.SetDNS(dnsServer string)` | `FOUNDATION_EXPORT void MobileSetDNS(NSString* _Nullable dnsServer);` | `MobileSetDNS(_:)` | void |
| `mobile.SetSocksListenHost(host string)` | `FOUNDATION_EXPORT void MobileSetSocksListenHost(NSString* _Nullable host);` | `MobileSetSocksListenHost(_:)` | void |
| `mobile.SetVP8Options(fps, batchSize int)` | `FOUNDATION_EXPORT void MobileSetVP8Options(long fps, long batchSize);` | `MobileSetVP8Options(_:_:)` | Go `int` → Obj-C `long` → Swift `Int` |
| `mobile.SetLivenessOptions(intervalMillis, timeoutMillis, failures int)` | `FOUNDATION_EXPORT void MobileSetLivenessOptions(long intervalMillis, long timeoutMillis, long failures);` | `MobileSetLivenessOptions(_:_:_:)` | same |
| `mobile.SetDebug(enabled bool)` | `FOUNDATION_EXPORT void MobileSetDebug(BOOL enabled);` | `MobileSetDebug(_:)` | Go `bool` → Obj-C `BOOL` → Swift `Bool` |
| `mobile.Start(carrierName, roomID, clientID, keyHex string, socksPort int, socksUser, socksPass string) error` | `FOUNDATION_EXPORT BOOL MobileStart(NSString* carrierName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, NSString* socksUser, NSString* socksPass, NSError** error);` | `MobileStart(_, _, _, _, _, _, _, &err) -> Bool` | **Not auto-throws.** Swift sees the raw Obj-C signature; pass `NSErrorPointer` and inspect the `Bool` return. |
| `mobile.StartWithTransport(carrierName, transportName, roomID, clientID, keyHex string, socksPort int, socksUser, socksPass string) error` | `FOUNDATION_EXPORT BOOL MobileStartWithTransport(NSString* carrierName, NSString* transportName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, NSString* socksUser, NSString* socksPass, NSError** error);` | `MobileStartWithTransport(_, _, _, _, _, _, _, _, &err) -> Bool` | same |
| `mobile.Check(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis, vp8FPS, vp8BatchSize int) (int64, error)` | `FOUNDATION_EXPORT BOOL MobileCheck(NSString* carrierName, NSString* transportName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, long timeoutMillis, long vp8FPS, long vp8BatchSize, int64_t* ret0_, NSError** error);` | `MobileCheck(_, _, _, _, _, _, _, _, _, &ret, &err) -> Bool` | The `int64_t* ret0_` stays a real out-parameter; pass `inout Int64`. |
| `mobile.Ping(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis int, pingURL string, vp8FPS, vp8BatchSize int) (int64, error)` | `FOUNDATION_EXPORT BOOL MobilePing(NSString* carrierName, NSString* transportName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, long timeoutMillis, NSString* pingURL, long vp8FPS, long vp8BatchSize, int64_t* ret0_, NSError** error);` | `MobilePing(_, _, _, _, _, _, _, _, _, _, &ret, &err) -> Bool` | same |
| `mobile.WaitReady(timeoutMillis int) error` | `FOUNDATION_EXPORT BOOL MobileWaitReady(long timeoutMillis, NSError** error);` | `MobileWaitReady(_, &err) -> Bool` | not throwing — see note below |
| `mobile.Stop()` | `FOUNDATION_EXPORT void MobileStop(void);` | `MobileStop()` | void |
| `mobile.IsRunning() bool` | `FOUNDATION_EXPORT BOOL MobileIsRunning(void);` | `MobileIsRunning()` → `Bool` | non-throwing |
| `mobile.SetLogWriter(w LogWriter)` | `FOUNDATION_EXPORT void MobileSetLogWriter(id<MobileLogWriter> _Nullable w);` | `MobileSetLogWriter(_:)` | see section 3 |
| `mobile.SetProtector(p SocketProtector)` | `FOUNDATION_EXPORT void MobileSetProtector(id<MobileSocketProtector> _Nullable p0);` | `MobileSetProtector(_:)` | **Android-only**; ignore from iOS (ADR-0001) |

---

## 3. Log writer support

The Go `LogWriter` interface surfaces as an Obj-C protocol **and** a
same-named class (gomobile emits both — a Go-backed concrete class for
returning instances *from* Go, and a protocol for Swift-implemented
writers passed *into* Go):

```objc
@protocol MobileLogWriter <NSObject>
- (void)writeLog:(NSString* _Nullable)msg;
@end

@interface MobileLogWriter : NSObject <goSeqRefInterface, MobileLogWriter> { … }
```

Because both share the name `MobileLogWriter`, Swift's Obj-C importer
renames the **protocol** to `MobileLogWriterProtocol` (and keeps the
class as `MobileLogWriter`). A Swift type that wants to receive log
lines from Go must conform to the renamed protocol, **not** the class:

```swift
import OlcRTCMobile

// CORRECT — conforms to the renamed protocol:
class SwiftLogWriter: NSObject, MobileLogWriterProtocol {
    func writeLog(_ msg: String?) {
        // sanitize + forward to app log sink
    }
}

// WRONG — Swift reads this as multiple inheritance from two classes:
// class SwiftLogWriter: NSObject, MobileLogWriter { ... }
```

Pass an instance to `MobileSetLogWriter(_:)`. Sanitization (per
ADR-0010) is still Swift's job; the bridge is just the raw log line.

---

## 4. Compile-validated unknowns

- **Swift call syntax:** Confirmed that free functions keep the
  `Mobile` prefix in Swift (not lowercased). Argument labels are
  positional `_:` for all parameters (gomobile does not emit named
  Obj-C parameters for Go functions with multiple string args).
- **Throwing vs. non-throwing:** Initial assumption (verified
  **WRONG** during the
  [Wire Local Proxy Mode](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26591390505)
  compile attempt) was that Go `error` returns would import as Swift
  `throws`. They do **not**. The generated gomobile signatures use the
  generic `BOOL fn(..., NSError** error)` shape, and the Swift
  importer does **not** convert them to throwing functions (the symbol
  names don't fit the importer's Foundation-method-family
  heuristics). Each call site must:
  1. allocate `var err: NSError?` (and, for `Check`/`Ping`, also
     `var ret: Int64 = 0`),
  2. pass them by pointer (`&err`, `&ret`),
  3. branch on the `Bool` return: throw `err ?? <fallbackError>` when
     the call returned `false`, otherwise use the out value.

  Confirmed working Swift call shapes (from `RealOlcRTCService.swift`):

  ```swift
  // Start with explicit transport:
  var err: NSError?
  let ok = MobileStartWithTransport(
      carrier, transport, roomID, clientID, keyHex,
      socksPort, "", "", &err
  )
  if !ok { throw err ?? RealOlcRTCServiceError.startFailed }

  // WaitReady:
  var err: NSError?
  let ok = MobileWaitReady(timeoutMillis, &err)
  if !ok { throw err ?? RealOlcRTCServiceError.waitReadyFailed }

  // Check (returns Int64 via out-param):
  var ret: Int64 = 0
  var err: NSError?
  let ok = MobileCheck(
      carrier, transport, roomID, clientID, keyHex,
      socksPort, timeoutMillis, vp8FPS, vp8BatchSize,
      &ret, &err
  )
  if !ok { throw err ?? RealOlcRTCServiceError.checkFailed }
  // use `ret`

  // Ping (returns Int64 via out-param):
  var ret: Int64 = 0
  var err: NSError?
  let ok = MobilePing(
      carrier, transport, roomID, clientID, keyHex,
      socksPort, timeoutMillis, pingURL, vp8FPS, vp8BatchSize,
      &ret, &err
  )
  if !ok { throw err ?? RealOlcRTCServiceError.pingFailed }
  // use `ret`
  ```

- **`MobileLogWriter` naming clash:** Confirmed (above) that Swift
  renames the protocol to `MobileLogWriterProtocol` when there is a
  same-named class. Conform Swift types to
  `MobileLogWriterProtocol`, not `MobileLogWriter`.
- **`APPLICATION_EXTENSION_API_ONLY` safety:** Not yet validated. The
  `PacketTunnelProvider` extension is built with
  `APPLICATION_EXTENSION_API_ONLY: YES`; if gomobile pulls in any
  app-only API, the extension will refuse to link. The first Swift
  integration attempt for the extension will surface this if it is a
  problem. For now, only the main app target links the framework.
- **`SetLogWriter(nil)` legality:** The Obj-C signature is
  `_Nullable`, so Swift can pass `nil`. The Go side treats
  `w == nil` as a no-op (resets to default `log.SetOutput`), so this
  is safe.
- **`libresolv` is required** for any target that links
  `OlcRTCMobile.xcframework`. The Go runtime/stdlib references the
  BSD resolver symbols `_res_9_nclose`, `_res_9_ninit`, and
  `_res_9_nsearch`, which live in `libresolv.tbd` on iOS and are
  **not** linked by default. Discovered during the Debug
  iphonesimulator link in workflow run
  [26592753259](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26592753259)
  (`ld: Undefined symbols ... _runtime.text in OlcRTCMobile(go.o)`).
  The fix is `OTHER_LDFLAGS: $(inherited) -lresolv` on the linking
  target. Currently applied to **both** the main app target and the
  `PacketTunnelProvider` extension target (as of the
  `packet-tunnel-gomobile-probe` branch — see Milestone 3 in
  `docs/ROADMAP.md`). The symbol comes from the Go runtime, not from
  anything app-vs-extension specific, so any target that links
  `OlcRTCMobile.xcframework` needs the flag.

### Extension-target linking (probe in progress)

The `PacketTunnelProvider` extension target also links
`OlcRTCMobile.xcframework` under `APPLICATION_EXTENSION_API_ONLY =
YES` as of the `packet-tunnel-gomobile-probe` branch. This is a
**link probe only** — `Sources/PacketTunnelProvider/GomobileExtensionProbe.swift`
exposes `GomobileExtensionProbe.touchNonStartingAPI()`, which
references `MobileIsRunning()` and `MobileSetDebug(false)`. As of
probe v9 that helper is called from
`PacketTunnelProvider.startTunnel` immediately before the existing
`StubError.notWiredYet` failure, so the reference is reachable from
the extension's `NSExtensionPrincipalClass` — a runtime entrypoint
ld_prime cannot strip without breaking the extension contract.
The extension still does NOT call any `MobileStart*` /
`MobileCheck` / `MobilePing` and does NOT bring up a tunnel.

Probe history (full chain in `docs/ai/TASK_LOG.md`): v2–v8 tried
progressively more aggressive artificial anchors — Swift stored
properties, `-Wl,-u` linker forces, `-Wl,-needed_framework`, C
functions with `__attribute__((used, noinline, optnone))`, static
function-pointer initializers, `__attribute__((constructor))` —
and every one was stripped by ld_prime's regular dead-strip on
Xcode 16.4 / iOS 18.5 SDK. v9 abandons the anchor approach
entirely and uses the real `startTunnel` entrypoint instead.

Known risks the probe is intended to surface (record findings here
once a CI run is available):

1. **Extension-unsafe APIs from the Go runtime.** With
   `APPLICATION_EXTENSION_API_ONLY = YES`, the Swift / Obj-C
   compiler rejects any call into a symbol marked
   `__API_UNAVAILABLE(app_extension)`. If the Go runtime imports
   one transitively, the failure surfaces at compile time with a
   "is unavailable in application extensions" diagnostic naming
   the symbol.
2. **Undefined symbols at link time.** Additional BSD / system
   libraries beyond `libresolv` (e.g. `libnetwork`, `CFNetwork`
   privates) that the host app already happens to pull in via UI
   frameworks but the extension does not. Surfaces as
   `ld: Undefined symbols for architecture arm64: "_<symbol>"`.
3. **Xcode refusing a dynamic framework inside an app
   extension.** Less common since iOS 8, but possible if the
   framework's `Info.plist` or the extension's `Bundle` build
   settings disagree (e.g. mismatched `MinimumOSVersion`).
   Surfaces as a `PBXResourcesBuildPhase` / "Embedded binary
   linker error".
4. **Other `APPLICATION_EXTENSION_API_ONLY` violations** from the
   shared Swift sources (`Sources/Shared/Services/*.swift`).
   `URLSession` is extension-safe; `UIPasteboard` (used by the
   app's `LogsView`, not by the extension) is not. The shared
   sources currently only touch Foundation, so this is unlikely,
   but the probe will catch any regression that pulls in a UI
   symbol.
5. **Unsigned extension embedding issues.** With
   `CODE_SIGNING_ALLOWED=NO` the host app embeds the extension
   without signing it; some Xcode versions complain about
   `Embed App Extensions` on `iphoneos` when no identity exists.
   The host-app pipeline (`iOS App + Gomobile Build`) is already
   green with this same setting, so we expect this to be a
   non-issue — but recorded here for completeness.

If the probe's CI run goes red, the first relevant error block
from `xcodebuild` plus the `otool -L` output of the extension
binary gets pasted under this section as the verbatim record. If
the probe goes green, the section is updated to read **"compile
+ link confirmed under APPLICATION_EXTENSION_API_ONLY = YES"**
plus the workflow run URL, and Milestone 3 in `docs/ROADMAP.md`
flips its first task to `[x]`.

---

## How to refresh this file

1. Trigger `Gomobile iOS Bind` (e.g.
   `gh workflow run gomobile-ios-bind.yml --repo artpm4250-png/olcrtc-ios --ref main`).
2. Once green, download the `gomobile-inspection-report` artifact.
3. Read `summary.md`, `headers.txt`, `modulemaps.txt`, and (if any)
   `swiftinterfaces.txt`.
4. Fill in sections 1–4 above with verbatim names.
5. Commit this file with a message like
   `docs: refresh GOMOBILE_BINDINGS.md from CI inspection report`.
