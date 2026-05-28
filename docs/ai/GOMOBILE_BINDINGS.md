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

## Status

Pending first inspection run. The script + workflow have been updated
to emit the inspection reports as a CI artifact; this file will be
updated from that artifact in a follow-up commit so we record the
real symbol names rather than guessing.

The Go-side surface (defined in `third_party/olcrtc/mobile/mobile.go`)
that the bindings are derived from:

- `func SetProviders()`
- `func SetTransport(transport string)`
- `func SetDNS(dnsServer string)`
- `func SetSocksListenHost(host string)`
- `func SetVP8Options(fps, batchSize int)`
- `func SetLivenessOptions(intervalMillis, timeoutMillis, failures int)`
- `func SetDebug(enabled bool)`
- `func Start(carrierName, roomID, clientID, keyHex string, socksPort int, socksUser, socksPass string) error`
- `func StartWithTransport(carrierName, transportName, roomID, clientID, keyHex string, socksPort int, socksUser, socksPass string) error`
- `func Check(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis, vp8FPS, vp8BatchSize int) (int64, error)`
- `func Ping(carrierName, transportName, roomID, clientID, keyHex string, socksPort, timeoutMillis int, pingURL string, vp8FPS, vp8BatchSize int) (int64, error)`
- `func WaitReady(timeoutMillis int) error`
- `func Stop()`
- `func IsRunning() bool`
- `func SetLogWriter(w LogWriter)` (with `type LogWriter interface { WriteLog(msg string) }`)
- `func SetProtector(p SocketProtector)` — **Android-only**; ignore from iOS (ADR-0001).

## Sections to fill in after first inspection

These will be populated from the `gomobile-inspection-report` artifact:

### 1. Framework + module + import names

- `OlcRTCMobile.xcframework` slice paths (e.g. `ios-arm64/`, `ios-arm64_x86_64-simulator/`).
- Inner `*.framework` name as it appears on disk.
- The `module.modulemap` framework directive (this is what Swift sees
  as `import <Name>`).
- Bridging header path (if gomobile emitted one) vs. modular import.

### 2. Generated symbol mapping (Go → Obj-C → Swift)

Each row will record:

| Go symbol | Obj-C `@interface` / function | Swift name | Notes |
|-----------|-------------------------------|------------|-------|
| `mobile.Start(...)` | _to be filled_ | _to be filled_ | error-returning; gomobile flattens `(error)` into an `NSError**` out-param |
| `mobile.StartWithTransport(...)` | _to be filled_ | _to be filled_ | same flattening |
| `mobile.Check(...)` | _to be filled_ | _to be filled_ | returns `(int64, error)` — gomobile turns this into a `NSNumber*` / `NSError**` pair in Obj-C; Swift sees a throwing function returning `Int64` |
| `mobile.Ping(...)` | _to be filled_ | _to be filled_ | same as Check |
| `mobile.Stop()` | _to be filled_ | _to be filled_ | void |
| `mobile.IsRunning()` | _to be filled_ | _to be filled_ | returns `BOOL` |
| `mobile.WaitReady(...)` | _to be filled_ | _to be filled_ | error-returning |
| `mobile.SetTransport(...)` etc. | _to be filled_ | _to be filled_ | void setters |
| `mobile.SetLogWriter(w LogWriter)` | _to be filled_ | _to be filled_ | `LogWriter` becomes an Obj-C `@protocol` with a single `-writeLog:` method; Swift implements it via a class conforming to the protocol |

### 3. Log writer support

Whether the generated `LogWriter` protocol surfaces in the iOS
bindings (it normally does — gomobile emits `id<LogWriter>` for any
interface used as a parameter type). Sanitization (per ADR-0010) is
still Swift's job; the bridge is just `WriteLog(NSString *msg)`.

### 4. Unknowns / requires Swift compile validation

- Whether `int` arguments on the Go side surface as `NSInteger` or
  `jlong`-equivalent (`int64_t`) in the Obj-C header — gomobile picks
  per platform.
- Whether the framework declares `APPLICATION_EXTENSION_API_ONLY`-safe
  symbols (the `PacketTunnelProvider` extension is built with
  `APPLICATION_EXTENSION_API_ONLY: YES`; if gomobile pulls in any
  app-only API, the extension will refuse to link). The first Swift
  integration attempt will surface this if it is a problem.
- Whether `SetLogWriter(nil)` is legal — the Go side treats `w == nil`
  as a no-op, but gomobile may have nullability annotations that
  reject `nil`.

## How to refresh this file

1. Trigger `Gomobile iOS Bind` (e.g.
   `gh workflow run gomobile-ios-bind.yml --repo artpm4250-png/olcrtc-ios --ref main`).
2. Once green, download the `gomobile-inspection-report` artifact.
3. Read `summary.md`, `headers.txt`, `modulemaps.txt`, and (if any)
   `swiftinterfaces.txt`.
4. Fill in sections 1–4 above with verbatim names.
5. Commit this file with a message like
   `docs: refresh GOMOBILE_BINDINGS.md from CI inspection report`.
