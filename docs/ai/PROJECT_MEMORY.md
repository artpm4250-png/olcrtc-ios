# PROJECT_MEMORY.md

Persistent project state for the iOS client. Read this on every new
Claude session before touching code. Update it when the underlying
facts change — not when an individual task progresses (that belongs in
`TASK_LOG.md`).

## Repository identity

This is **`artpm4250-png/olcrtc-ios`** — a **standalone** iOS-client
repo. The Go core is **not** in this repo; it is consumed as a git
submodule under `third_party/olcrtc/` pinned to branch `fix/all` of
[`openlibrecommunity/olcrtc`](https://github.com/openlibrecommunity/olcrtc).

iOS app code, GitHub Actions, project-memory files, and build scripts
all live here. Go source lives in upstream. No Go edits happen in this
repo — they happen upstream, and we bump the submodule pointer.

## What olcRTC is

olcRTC is an encrypted TCP-over-WebRTC tunnel written in Go. Traffic
is disguised as a regular video call on whitelisted SFU services
(Jitsi, Yandex Telemost, WbStream, etc.). The data path looks like:

```
app -> SOCKS5 -> olcrtc client -> WebRTC/SFU -> olcrtc server -> internet
```

Inside the WebRTC channel: XChaCha20-Poly1305 + smux. The upstream
repo also exposes the same client logic as a gomobile-friendly
package at `mobile/` (in this repo: `third_party/olcrtc/mobile/`),
which is already used to build the Android library.

Relevant artifacts in the upstream submodule:

- `third_party/olcrtc/mobile/mobile.go` — gomobile-compatible API.
  Exported entry points include `SetProviders`, `SetTransport`,
  `SetDNS`, `SetSocksListenHost`, `SetVP8Options`,
  `SetLivenessOptions`, `SetDebug`, `Start`, `StartWithTransport`,
  `Check`, `Ping`, `WaitReady`, `Stop`, `IsRunning`, `SetLogWriter`,
  `SetProtector` (Android-only; iOS uses `NEPacketTunnelFlow`
  instead). This is the surface we will bind into Swift.
- `third_party/olcrtc/docs/uri.md` — `olcrtc://` URI format
  (client-side convention, parsed by the iOS app, not by Go).
- `third_party/olcrtc/docs/sub.md` — subscription file format
  (plain-text list of `olcrtc://` URIs plus metadata, hosted over
  HTTPS).
- `third_party/olcrtc/docs/configuration.md`, `manual.md`,
  `settings.md` — config / transport / liveness knobs that the iOS UI
  needs to surface or pass through to Go.

## Goal of this repo

Ship a **native iOS VPN client** for olcRTC with **two modes**:

### 1. VPN Mode (real iOS VPN architecture)

- SwiftUI container app provisions and controls a system VPN
  configuration through `NETunnelProviderManager`.
- A separate **`NetworkExtension` `PacketTunnelProvider` target**
  hosts the actual tunnel runtime. The Go core
  (`OlcRTCMobile.xcframework`, built from
  `third_party/olcrtc/mobile/`) runs inside the extension process,
  not in the main app.
- This is real Apple VPN architecture, not a simulation. The
  architecture must be ready for runtime on a real iPhone — but
  **runtime on a real device is unlocked later**, after:
  - an Apple Developer account is in place,
  - a provisioning profile scoped to the extension exists,
  - the `NetworkExtension` (Packet Tunnel) entitlement is granted,
  - the build is signed.
- Until those are in place, CI produces an **unsigned `.ipa`
  artifact** for inspection / later signing. We do not promise that
  this IPA will install and run a VPN on a stock iPhone.

### 2. Local Proxy Mode (foreground compatibility / testing)

- Foreground mode in the main app that uses the existing olcRTC
  SOCKS / local-proxy capability via the gomobile API.
- Useful for:
  - third-party VPN/proxy apps that accept a SOCKS endpoint,
  - manual per-app or system proxy configuration that points at a
    local endpoint,
  - testing the Go core without going through the extension flow.
- Endpoint is shown in the UI, e.g. `127.0.0.1:8808` (port chosen by
  the user or default).
- Selectable in the UI **separately** from VPN Mode. The user picks
  one mode at a time; the UI makes clear which is active.
- **Background limitation, surfaced honestly:** a normal iOS app
  process can be suspended in the background. Running another VPN
  app does not guarantee iOS keeps our process alive. Therefore
  Local Proxy Mode is **not** a reliable background runtime. The
  only background-safe proxy/VPN runtime on iOS is inside the
  `NetworkExtension` target — see VPN Mode.

### Shared MVP feature set (both modes)

- Profile management (create / edit / delete / select).
- `olcrtc://` URI import.
- Subscription import (HTTPS fetch of a `sub.md`-style list).
- Start / Stop (driving the active mode).
- Check (validate profile fields) and Ping (HTTP ping through the
  tunnel via the Go layer).
- Sanitized logs visible in-app.

## Hard constraints (environmental)

These shape every architectural choice today:

- No Mac is available to the user. All builds must run on a GitHub
  Actions macOS runner. Local Xcode workflows are not an option.
- **Today**, CI requires no Apple Developer account, no provisioning
  profile, no signing identity, no TestFlight, no App Store Connect,
  and no manual interaction in Xcode. The project must be generatable
  / buildable from the command line.
- Output of CI today is a passing scaffold build (no `.ipa` yet).
  The eventual artifact is an **unsigned `.ipa`** uploaded as a
  workflow artifact — a build / later-signing artifact, not a
  runnable VPN.
- **Tomorrow**, runtime on a real iPhone for VPN Mode requires
  signing + provisioning + the `NetworkExtension` entitlement. The
  architecture is designed so that adding those later does not
  require redesign — only configuration.

## Out of scope today (explicitly later or never)

- **Later (architecture-ready, runtime not yet):**
  - Signing the IPA, configuring a provisioning profile, requesting
    the `NetworkExtension` entitlement, installing on a real iPhone,
    running VPN Mode end-to-end on device.
  - TestFlight / App Store distribution.
- **Never (in this repo):**
  - Editing the Go source under `third_party/olcrtc/`. That repo
    is upstream; changes go there.
  - Fake VPN functionality — UI that pretends a tunnel is active
    when it is not, "Connect" toggles that do nothing, simulated
    tunnel states.
  - Logging `keyHex`, passwords, or secret-bearing URIs anywhere.

## Security / privacy invariants

- `keyHex` and passwords must never reach the in-app log view, the
  system log, files on disk in plaintext beyond the profile store,
  or crash reports. Mask before display. This applies equally to
  logs emitted from the `PacketTunnelProvider` extension and from
  the container app.
- Subscription URLs may contain credentials; treat them like
  profiles — do not echo them into logs.
- Profile storage location and at-rest protection are deliberately
  not decided yet; see `DECISIONS.md` once that ADR lands. The
  store must be reachable from both the main app and the
  `PacketTunnelProvider` extension (App Group / shared container is
  the likely answer).

## Where things live

```
ios/OlcRTCClient/              — Xcode project (XcodeGen project.yml + sources)
  project.yml                  — source of truth for the Xcode project
  Sources/App/                 — SwiftUI container app target
  Sources/PacketTunnelProvider/— NetworkExtension PacketTunnelProvider target (stub today)
  Sources/Shared/              — code compiled into both targets and the tests target
  Tests/OlcRTCClientTests/     — XCUnitTest target
scripts/                       — build helpers (placeholder; gomobile bind script lands later)
.github/workflows/
  ios-scaffold.yml             — scaffold-only CI on macos-latest
third_party/olcrtc/            — git submodule, openlibrecommunity/olcrtc @ fix/all
docs/ai/                       — the three durable memory files
```

The generated `.xcodeproj` is **not** committed. `project.yml` is the
source of truth (see ADR-0007). `OlcRTCMobile.xcframework` is **not**
committed; it gets built by `scripts/ios-bind.sh` in a later step.
