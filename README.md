# olcrtc-ios

Native iOS client for [olcRTC](https://github.com/openlibrecommunity/olcrtc).

This is a **standalone** repository, separate from the Go core upstream.
The upstream is consumed as a git submodule under `third_party/olcrtc`.

## Status (current)

- **Standalone iOS client repository** for olcRTC — not a fork, not a
  subdirectory of upstream.
- **Upstream Go core** is a git submodule:
  [`third_party/olcrtc`](third_party/olcrtc) → branch `fix/all` of
  [`openlibrecommunity/olcrtc`](https://github.com/openlibrecommunity/olcrtc).
  Never edited from this repo (see `CLAUDE.md` and ADR-0011).
- **Green CI workflow**:
  [`iOS App + Gomobile Build`](.github/workflows/ios-app-gomobile.yml)
  on `macos-latest` — runs `gomobile bind` → `xcodegen generate` →
  Debug iphonesimulator build → tests → Release iphoneos generic
  build → unsigned IPA packaging.
- **CI artifact**: `OlcRTCClient-unsigned-ipa` (`build/ipa/OlcRTCClient-unsigned.ipa`).
- **Local Proxy Mode** is wired to the **real gomobile API** in the
  main app target via `OlcRTCMobile.xcframework`
  (`Start` / `Stop` / `Check` / `Ping` / `IsRunning` / `WaitReady` /
  `SetLogWriter`). Local Proxy Mode is foreground-only and not
  background-reliable on iOS by design (ADR-0005).
- **VPN Mode** / `PacketTunnelProvider` exists as a **scaffold / stub
  target only**. The extension is a real `NEPacketTunnelProvider`
  subclass that fails fast with `notWiredYet`; it does **not** link
  `OlcRTCMobile.xcframework` and does **not** pretend to tunnel
  anything. Wiring it is a later step.
- **Unsigned IPA** is a **CI / later-signing artifact only**. It is
  **not** expected to install or run a VPN on an ordinary iPhone.
  Doing that requires all of: a paid Apple Developer account, a
  provisioning profile scoped to the `PacketTunnelProvider`'s bundle
  ID, the `com.apple.developer.networking.networkextension`
  entitlement, and a signed build with those attached. None of those
  are configured here today (ADR-0008).

## Read me before touching anything

If you are an AI assistant or a new contributor, read these in order:

1. [`CLAUDE.md`](CLAUDE.md) — pre-flight rules.
2. [`docs/ai/PROJECT_MEMORY.md`](docs/ai/PROJECT_MEMORY.md) — what this
   project is, the goal, and the hard environmental constraints.
3. [`docs/ai/DECISIONS.md`](docs/ai/DECISIONS.md) — architectural
   decisions already locked in.
4. [`docs/ai/TASK_LOG.md`](docs/ai/TASK_LOG.md) — what is done, what
   broke, what to do next.

## Layout

```
CLAUDE.md                        — AI pre-flight
docs/ai/                         — durable project memory
ios/OlcRTCClient/                — SwiftUI app + PacketTunnelProvider + tests
.github/workflows/               — CI workflows
scripts/                         — build helpers (gomobile bind)
third_party/olcrtc/              — git submodule: openlibrecommunity/olcrtc @ fix/all
```

## Cloning

```sh
git clone --recurse-submodules https://github.com/artpm4250-png/olcrtc-ios.git
# or, after a plain clone:
git submodule update --init --recursive
```

## CI workflows

- [`iOS App + Gomobile Build`](.github/workflows/ios-app-gomobile.yml)
  — primary integrated workflow. Builds `OlcRTCMobile.xcframework`
  from the upstream submodule, generates the Xcode project, compiles
  Debug for `iphonesimulator`, runs unit tests, compiles Release for
  `iphoneos` (generic, unsigned), validates the produced `.app`
  bundle, packages it into `OlcRTCClient-unsigned.ipa`, and uploads
  the `OlcRTCClient-unsigned-ipa` workflow artifact.
- [`Gomobile iOS Bind`](.github/workflows/gomobile-ios-bind.yml)
  — isolated check: runs `gomobile bind` and uploads the framework
  + a mechanical inspection report.
- [`iOS Scaffold Build`](.github/workflows/ios-scaffold.yml)
  — scaffold-only check (no Go core).

Trigger via `workflow_dispatch` or by pushing changes to the relevant
paths (see each workflow file's `on:` block).

## Distribution status

CI produces an **unsigned** `.ipa` artifact
(`OlcRTCClient-unsigned-ipa`) suitable only for inspection or later
re-signing. The unsigned build will **not** install and run as a VPN
on a stock iPhone — that requires Apple signing + provisioning + the
`NetworkExtension` entitlement (none configured here).
