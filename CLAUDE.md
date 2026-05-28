# CLAUDE.md

Mandatory pre-flight for any Claude / AI session working in this
repository. Read this file first, then read the three project memory
files **before doing anything else** (do not edit code, do not propose
plans, do not run builds until these are loaded into context):

1. [`docs/ai/PROJECT_MEMORY.md`](docs/ai/PROJECT_MEMORY.md) — what this
   project is, the goal of the iOS client (dual-mode: VPN Mode + Local
   Proxy Mode), and the hard environmental constraints (no Mac, GitHub
   Actions only, unsigned today).
2. [`docs/ai/DECISIONS.md`](docs/ai/DECISIONS.md) — architectural
   decisions that are already locked in. Do not relitigate these
   without writing a new decision entry first.
3. [`docs/ai/TASK_LOG.md`](docs/ai/TASK_LOG.md) — what has been done,
   what broke, and what to do next. Update this file at the end of
   every working session so the next session can pick up cold.

These three files are the source of truth for this repo. If something
in this conversation contradicts them, the files win until they are
updated.

## Repository identity

This is **`artpm4250-png/olcrtc-ios`** — a **standalone** iOS-client
repository. It is **not** a fork or a subdirectory of the upstream Go
core. The upstream lives at
[`openlibrecommunity/olcrtc`](https://github.com/openlibrecommunity/olcrtc)
and is consumed here as a git submodule pinned to branch `fix/all`
under `third_party/olcrtc/`. Do **not** push iOS scaffold changes to
the upstream and do **not** open a PR against upstream without an
explicit instruction.

Repo layout:

```
CLAUDE.md
README.md
docs/ai/                       — durable project memory (this folder + the three files above)
ios/OlcRTCClient/              — SwiftUI app + PacketTunnelProvider extension + tests
.github/workflows/             — CI (ios-scaffold.yml today)
scripts/                       — build helpers (gomobile bind etc., placeholder for now)
third_party/olcrtc/            — git submodule → openlibrecommunity/olcrtc @ fix/all
```

## Hard rules (do not violate without an explicit user override in chat)

- **No Mac available.** Every build path must work on a GitHub Actions
  macOS runner. Never assume the user can open Xcode, run `xcodebuild`
  locally, or click anything in a GUI.
- **Unsigned IPA is a CI / later-signing artifact only.** Today CI
  validates the scaffold builds (no `.ipa` yet). The eventual unsigned
  `.ipa` is a build / later-signing artifact. Do **not** claim that
  this IPA can be installed and run as a VPN on a stock iPhone —
  real-device VPN runtime requires an Apple Developer account, a
  provisioning profile scoped to `NetworkExtension`, the
  `NetworkExtension` entitlement, and a signed build. None of those
  are configured yet.
- **Do not fake VPN functionality.** Do not ship UI that pretends a
  tunnel is active when it is not, do not invent placeholder "Connect"
  toggles that do nothing, do not log success states for runs that did
  not happen.
- **Do implement real VPN architecture.** The product has two modes
  and both are real:
  - **VPN Mode** — SwiftUI container app + a `NetworkExtension`
    `PacketTunnelProvider` target, managed via
    `NETunnelProviderManager`. The architecture must be ready for a
    real device runtime once signing is available.
  - **Local Proxy Mode** — foreground app exposing a local SOCKS /
    proxy endpoint on `127.0.0.1:<port>` (e.g. `127.0.0.1:8808`) for
    use with third-party VPN/proxy apps, manual proxy configuration,
    and testing. Foreground Local Proxy Mode is **not**
    background-reliable on iOS — iOS may suspend the app. Surface this
    honestly in the UI. Background-safe proxy/VPN runtime must live
    inside the `NetworkExtension` target, not in the main app.
- **Go core stays external.** The Go core lives in
  `third_party/olcrtc/` (submodule). Bind the existing
  `third_party/olcrtc/mobile` package with
  `gomobile bind -target=ios` to produce `OlcRTCMobile.xcframework`.
  Both iOS targets will share that binary — the container app uses it
  for Local Proxy Mode, and the `PacketTunnelProvider` uses it for VPN
  Mode. **Never** edit the Go source under `third_party/olcrtc/` from
  this repo. If a Go change is genuinely required, raise it in chat,
  it gets done in the upstream repo, and we bump the submodule pointer
  here.
- **Sanitized logs.** Never log `keyHex`, passwords, or full
  subscription URLs containing secrets. Mask before writing to any log
  sink the UI can surface. This applies equally to the container app
  and to the `NetworkExtension` target.

## Scope of the iOS client

In scope: dual-mode client (VPN Mode + Local Proxy Mode), profile
management, `olcrtc://` URI import, subscription import, Start / Stop,
Check / Ping, sanitized logs, SwiftUI UI, gomobile-built
`OlcRTCMobile.xcframework`, `NetworkExtension` `PacketTunnelProvider`
target wired via `NETunnelProviderManager`, GitHub Actions workflows
that validate the scaffold today and produce an unsigned `.ipa`
artifact once gomobile is wired.

Out of scope (do not implement, do not stub UI for): App Store /
TestFlight distribution, fake "Connect" affordances that do nothing,
logging of secrets, configuring signing identities or provisioning
profiles in CI, promising that an unsigned IPA can install and run VPN
on a stock iPhone, modifications to the Go core source from this repo.

## Working agreement

- Before suggesting a change, name which of the three memory files it
  affects, and update that file in the same change.
- Prefer editing the existing memory files over inventing parallel docs.
- Keep `TASK_LOG.md` append-only inside its sections; do not rewrite history.
- If a constraint above blocks the requested task, say so explicitly and
  stop — do not silently work around it.
