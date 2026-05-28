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
  (models, URI parser, profile store, profile validator,
  subscription importer, log sanitizer). Convenient for the
  scaffold stage; once we have real cross-target data flow, this may
  be promoted to its own framework target.
- **`Tests/OlcRTCClientTests/`** — unit tests for the URI parser, the
  profile validator, the subscription importer, and the log
  sanitizer.

## UI usage (Local Proxy MVP)

The app has four tabs. Today only **Local Proxy Mode** is wired to a
real runtime; **VPN Mode** is a scaffold/stub and is labelled as such
in the UI.

- **Connect** — pick the mode, fill the profile fields (provider,
  transport, room ID, client ID, encryption key, SOCKS host/port,
  DNS, debug), and press **Start**. Inline validation runs on every
  field change; the **Start** button is disabled until the profile is
  valid. Validation rules:
  - provider ∈ {`jitsi`, `telemost`, `wbstream`},
  - transport ∈ {`datachannel`, `vp8channel`},
  - room ID and client ID must not be empty,
  - encryption key must be exactly 64 hex characters,
  - SOCKS port must be a number in `1…65535`.
- **Save as profile…** on the Connect tab stores the current form as
  a named profile. Profiles with the same
  (provider, transport, room, key, client ID) tuple are treated as
  duplicates and updated in place rather than appended.
- **Profiles** — list of saved profiles. Tap to load into the
  Connect form. Swipe-to-delete (or use Edit → Delete). The toolbar
  `+` menu offers two import flows:
  - **Import olcrtc:// URI** — paste a single
    `olcrtc://<provider>?<transport>@<room>#<key>$<mimo>` URI.
    Percent-encoded room and MIMO fields are decoded; the `$<mimo>`
    suffix is used as the profile's display name when present. The
    full URI and the key are never written to logs.
  - **Import subscription URL** — paste an `http://` or `https://`
    URL pointing to a plain-text subscription. Each non-empty line
    is parsed as a separate `olcrtc://` URI; lines starting with `#`
    are treated as comments and skipped; invalid lines are skipped
    with a sanitized reason (line number + structured error, never
    the raw line). The sheet shows an "X imported, Y skipped"
    summary after each import.
- **Logs** — running, sanitized log buffer. `LogSanitizer` masks
  64-char hex keys, full `olcrtc://` URIs, and `keyHex=` /
  `password=` style key/value pairs before they reach this view.
  The toolbar has **Copy** (copy all log lines to the pasteboard)
  and **Clear** (drop the in-memory log buffer).
- **About** — explicitly distinguishes Local Proxy Mode (wired) from
  VPN Mode (scaffold/stub), and explains the unsigned-IPA caveats.

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

## Unsigned IPA artifact (CI only)

The
[`iOS App + Gomobile Build`](../../.github/workflows/ios-app-gomobile.yml)
workflow now packages the Release `iphoneos` `.app` bundle into an
**unsigned** `.ipa` archive and uploads it as a workflow artifact:

- Artifact name: `OlcRTCClient-unsigned-ipa`
- Archive path inside the run: `build/ipa/OlcRTCClient-unsigned.ipa`
- Structure: a plain zip containing
  `Payload/OlcRTCClient.app/...`, no `_CodeSignature/`, no embedded
  provisioning profile.

This IPA exists strictly as a **CI / later-signing artifact**. It is
**not** expected to install or run a VPN on an ordinary iPhone. Real
on-device install — and especially VPN Mode runtime through the
`PacketTunnelProvider` extension — requires all of:

- a paid Apple Developer account;
- a provisioning profile scoped to the
  `PacketTunnelProvider` extension's bundle ID;
- the `com.apple.developer.networking.networkextension` entitlement;
- a signed build with that profile and entitlement attached.

None of those are configured in this repository today (see
ADR-0008). The artifact is meant to be consumed by a later signed-build
pipeline that re-signs and re-packages it, not to be sideloaded onto a
random device.

### IPA structure (validated by CI)

Every run unpacks the freshly-built `.ipa` and asserts the following
layout before declaring success — drift in any of these paths fails
the workflow loudly instead of shipping a broken artifact:

```
Payload/
  OlcRTCClient.app/
    Info.plist
    OlcRTCClient                                       # main app Mach-O (arm64)
    PkgInfo
    Frameworks/
      OlcRTCMobile.framework/
        Info.plist
        OlcRTCMobile                                   # gomobile dylib (arm64)
    PlugIns/
      PacketTunnelProvider.appex/
        Info.plist
        PacketTunnelProvider                           # extension Mach-O (arm64)
```

The CI step also asserts the following are **not** present in the
bundle:

- any `*.xcframework` directory (would mean Xcode embedded the
  multi-slice wrapper instead of the iphoneos slice);
- any `*.dSYM` or `*.swiftmodule` directory (development-only);
- any `embedded.mobileprovision` (signed-build artifact).

Bundle identifiers, version strings, and binary sizes are printed in
the same step for quick visual confirmation. As of the first validated
run, the main app binary statically links the Go runtime (≈38 MB),
while `OlcRTCMobile.framework`'s shared library itself is small
(≈33 KB) — most Go code ends up in the host binary because the
framework is built with gomobile's default `-buildmode=c-archive`
flow, not as a self-contained dylib.

## What is **not** here today

- The framework is not yet wired into `PacketTunnelProvider`. VPN Mode
  is still a compile-time stub.
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
