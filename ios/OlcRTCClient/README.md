# OlcRTCClient — iOS scaffold

SwiftUI + `NetworkExtension` scaffold for the olcRTC iOS client. This is
the project layout described by ADR-0003/0004/0006/0007 in
[`docs/ai/DECISIONS.md`](../../docs/ai/DECISIONS.md). Read
[`CLAUDE.md`](../../CLAUDE.md) and the three files under `docs/ai/`
before changing anything here.

## What is here today

- **`project.yml`** — XcodeGen spec; the source of truth for the Xcode
  project. The `.xcodeproj` is generated, never committed.
- **`Sources/App/`** — SwiftUI container app target (`OlcRTCClient`).
  Hosts the UI (Connect / Profiles / Logs / About) and the foreground
  Local Proxy Mode runtime.
- **`Sources/PacketTunnelProvider/`** — `NetworkExtension`
  `PacketTunnelProvider` target. **Compile-time stub** for VPN Mode —
  it exists as a real extension target but does **not** pretend the
  tunnel works yet. The Go runtime will be wired in a later step.
- **`Sources/Shared/`** — Swift sources compiled into both targets
  (models, URI parser, profile store, log sanitizer). Convenient for
  the scaffold stage; once we have real cross-target data flow, this
  may be promoted to its own framework target.
- **`Tests/OlcRTCClientTests/`** — unit tests for the parser and the
  log sanitizer.

## `OlcRTCMobile.xcframework` is generated, never committed

The Go core is consumed via the `third_party/olcrtc` submodule and
turned into `OlcRTCMobile.xcframework` by
[`scripts/build-gomobile-ios.sh`](../../scripts/build-gomobile-ios.sh)
(invoked locally on a Mac or on a macOS CI runner). The framework
lands at:

```
ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework
```

That path is **ignored by `.gitignore`** and must not be committed.
It is produced fresh on every CI run by the
[`Gomobile iOS Bind`](../../.github/workflows/gomobile-ios-bind.yml)
workflow (isolated bind + inspection report) and by the
[`iOS App + Gomobile Build`](../../.github/workflows/ios-app-gomobile.yml)
workflow (integrated build: gomobile bind + XcodeGen + xcodebuild).

The framework is currently linked **only** into the main app target
(`OlcRTCClient`). The `PacketTunnelProvider` extension is still
stubbed and does NOT link the framework yet — that happens in a later
step once `APPLICATION_EXTENSION_API_ONLY` compatibility is validated
(see the "Next" section of
[`docs/ai/TASK_LOG.md`](../../docs/ai/TASK_LOG.md)).

## What is **not** here today

- The framework is not yet wired into `PacketTunnelProvider`. VPN Mode
  is still a compile-time stub.
- No unsigned `.ipa` packaging yet. See the "Next" section of
  [`docs/ai/TASK_LOG.md`](../../docs/ai/TASK_LOG.md).
- No code signing identity, no real provisioning profile, no real
  `NetworkExtension` entitlement values. The `.entitlements` files
  under `Sources/App/` and `Sources/PacketTunnelProvider/` are kept in
  the repo as a future-signing reference but are **not** attached to
  any build configuration in `project.yml` today — Xcode would
  otherwise refuse to build unsigned because
  `com.apple.developer.networking.networkextension` requires a
  matching provisioning profile. When a signing identity is configured
  later, attach them via `CODE_SIGN_ENTITLEMENTS` in `project.yml`.
  See ADR-0008.
- No claim that the unsigned `.ipa` produced from this scaffold will
  install and run a VPN on a stock iPhone. It will not.

## Generating the Xcode project locally (Mac required)

```sh
cd ios/OlcRTCClient
brew install xcodegen   # one-time
xcodegen generate
open OlcRTCClient.xcodeproj
```

CI does the same thing without `open`. None of the project owners have
a Mac at the time of writing — see `CLAUDE.md` and
`docs/ai/PROJECT_MEMORY.md`.

## Future gomobile integration

`OlcRTCMobile.xcframework` (produced by
`gomobile bind -target=ios ./mobile`) is the planned bridge to the Go
core. Two open questions to resolve when wiring it in:

- **App target** — likely consumes the framework directly for Local
  Proxy Mode (`Start`, `Stop`, `Check`, `Ping`, `SetLogWriter`).
- **PacketTunnelProvider target** — may consume the framework directly,
  or via a thin adapter that exposes only what the extension needs
  (the extension has a tighter memory budget than the main app).
- **Cross-target linkage** — whether the same `xcframework` slice can
  be embedded into both the app and the extension binaries needs to be
  verified once we have a real CI build; if Apple's extension API
  restrictions ("APPLICATION_EXTENSION_API_ONLY = YES") flag any
  symbols, we will need a separate slice for the extension.

Until then, the app and extension only see Swift-side mocks and stubs.
