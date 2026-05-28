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
| `mobile.Start(carrierName, roomID, clientID, keyHex string, socksPort int, socksUser, socksPass string) error` | `FOUNDATION_EXPORT BOOL MobileStart(NSString* carrierName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, NSString* socksUser, NSString* socksPass, NSError** error);` | `try MobileStart(_:_:_:_:_:_:_:)` | Go `error` → Obj-C `BOOL` return + `NSError**` out-param → Swift throwing function |
| `mobile.StartWithTransport(carrierName, transportName, roomID, clientID, keyHex string, socksPort int, socksUser, socksPass string) error` | `FOUNDATION_EXPORT BOOL MobileStartWithTransport(NSString* carrierName, NSString* transportName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, NSString* socksUser, NSString* socksPass, NSError** error);` | `try MobileStartWithTransport(_:_:_:_:_:_:_:_:)` | same |
| `mobile.Check(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis, vp8FPS, vp8BatchSize int) (int64, error)` | `FOUNDATION_EXPORT BOOL MobileCheck(NSString* carrierName, NSString* transportName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, long timeoutMillis, long vp8FPS, long vp8BatchSize, int64_t* ret0_, NSError** error);` | `try MobileCheck(_:_:_:_:_:_:_:_:_:_:)` → `Int64` | Go `(int64, error)` → Obj-C `BOOL` + `int64_t* ret0_` + `NSError**` → Swift throwing function returning `Int64` (the out-param becomes the return value) |
| `mobile.Ping(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis int, pingURL string, vp8FPS, vp8BatchSize int) (int64, error)` | `FOUNDATION_EXPORT BOOL MobilePing(NSString* carrierName, NSString* transportName, NSString* roomID, NSString* clientID, NSString* keyHex, long socksPort, long timeoutMillis, NSString* pingURL, long vp8FPS, long vp8BatchSize, int64_t* ret0_, NSError** error);` | `try MobilePing(_:_:_:_:_:_:_:_:_:_:_:)` → `Int64` | same |
| `mobile.WaitReady(timeoutMillis int) error` | `FOUNDATION_EXPORT BOOL MobileWaitReady(long timeoutMillis, NSError** error);` | `try MobileWaitReady(_:)` | throwing |
| `mobile.Stop()` | `FOUNDATION_EXPORT void MobileStop(void);` | `MobileStop()` | void |
| `mobile.IsRunning() bool` | `FOUNDATION_EXPORT BOOL MobileIsRunning(void);` | `MobileIsRunning()` → `Bool` | non-throwing |
| `mobile.SetLogWriter(w LogWriter)` | `FOUNDATION_EXPORT void MobileSetLogWriter(id<MobileLogWriter> _Nullable w);` | `MobileSetLogWriter(_:)` | see section 3 |
| `mobile.SetProtector(p SocketProtector)` | `FOUNDATION_EXPORT void MobileSetProtector(id<MobileSocketProtector> _Nullable p0);` | `MobileSetProtector(_:)` | **Android-only**; ignore from iOS (ADR-0001) |

---

## 3. Log writer support

The Go `LogWriter` interface surfaces as an Obj-C protocol:

```objc
@protocol MobileLogWriter <NSObject>
- (void)writeLog:(NSString* _Nullable)msg;
@end
```

Swift implements it via a class conforming to `MobileLogWriter`:

```swift
import OlcRTCMobile

class SwiftLogWriter: NSObject, MobileLogWriter {
    func writeLog(_ msg: String?) {
        // sanitize + forward to app log sink
    }
}
```

Pass an instance to `MobileSetLogWriter(_:)`. Sanitization (per
ADR-0010) is still Swift's job; the bridge is just the raw log line.

---

## 4. Compile-validated unknowns

- **Swift call syntax:** Confirmed that free functions keep the
  `Mobile` prefix in Swift (not lowercased). Argument labels are
  positional `_:` for all parameters (gomobile does not emit named
  Obj-C parameters for Go functions with multiple string args).
- **Throwing vs. non-throwing:** Confirmed that Go `error` return
  imports as Swift `throws`, and Go `(int64, error)` imports as
  `throws -> Int64` (the `int64_t* ret0_` out-param becomes the Swift
  return value).
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
