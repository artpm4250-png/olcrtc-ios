# DECISIONS.md

Architectural decisions for the iOS client track. Each decision is durable:
do not silently override one — append a new entry that supersedes it and
link the old one. Format is a lightweight ADR.

Status values: `Accepted`, `Superseded by ADR-NNN`, `Proposed`.

---

## ADR-0001 — Reuse the existing Go `./mobile` package via `gomobile bind -target=ios`

- **Status:** Accepted
- **Context:** The Go core (`internal/client`, `internal/control`,
  transports, session management) already exposes a gomobile-friendly API
  in `mobile/mobile.go` in the upstream repo and is consumed by the
  Android client this way. The iOS client needs the same logic, not a
  reimplementation. In this repo the Go source lives under the submodule
  `third_party/olcrtc/` (see ADR-0011).
- **Decision:** Build `OlcRTCMobile.xcframework` from
  `third_party/olcrtc/mobile` using `gomobile bind -target=ios` and link
  it into both iOS targets — the SwiftUI container app (for Local Proxy
  Mode) and the `PacketTunnelProvider` `NetworkExtension` (for VPN
  Mode). The Swift layer does **not** reimplement protocol, transport,
  or crypto code.
- **Consequences:**
  - Single source of truth for protocol behavior across platforms.
  - Both iOS targets inherit the same exported surface (`Start`,
    `StartWithTransport`, `Check`, `Ping`, `Stop`, `IsRunning`,
    `WaitReady`, `SetLogWriter`, `SetTransport`, etc.).
  - `SetProtector` (Android VPN socket protection) does not apply on
    iOS; the equivalent on iOS is handled by routing traffic through
    `NEPacketTunnelFlow` inside the extension. Do not call
    `SetProtector` from iOS code.
  - Toolchain pinning (Go version, gomobile version, Xcode version) lives
    in the CI workflow when it is introduced; until then it is undefined.

---

## ADR-0002 — UI framework: SwiftUI, iOS 16+ baseline

- **Status:** Accepted
- **Context:** The container app needs a small set of screens (profile
  list, profile editor, import dialogs, mode selector, run/log view). No
  legacy iOS support requirement. The `PacketTunnelProvider` extension is
  not a UI surface.
- **Decision:** SwiftUI as the only UI framework in the container app.
  Target iOS 16 or newer. No UIKit unless a specific control is missing in
  SwiftUI, in which case wrap it locally.
- **Consequences:**
  - Smaller, more declarative codebase.
  - Excludes users on iOS < 16; acceptable for a client that ships as an
    unsigned IPA to a technical audience and is later signed for a
    similarly current device base.

---

## ADR-0003 — Dual-mode iOS client: VPN Mode and Local Proxy Mode

- **Status:** Accepted
- **Supersedes:** the earlier "foreground SOCKS, not a VPN" stance from
  the previous revision of this file.
- **Context:** Two distinct user needs:
  1. A real iOS VPN that captures system traffic and routes it through
     olcRTC. This is what most users will want long-term.
  2. A local SOCKS / proxy endpoint for compatibility with third-party
     VPN/proxy apps, manual proxy configuration, and testing the Go core
     without going through the system VPN flow.
- **Decision:** The iOS client ships with both modes. The user selects one
  at a time in the UI; they are mutually exclusive at runtime. Both modes
  use the same Go core via `OlcRTCMobile.xcframework`.
- **Consequences:**
  - The UI has a mode selector and clearly indicates which mode is active.
  - Profile data is shared between modes via an App Group / shared
    container (location TBD in a follow-up ADR).
  - Documentation and UI copy must distinguish the two modes so users do
    not confuse Local Proxy Mode's foreground limitation with VPN Mode's
    background-safe runtime.

---

## ADR-0004 — VPN Mode uses `NetworkExtension` `PacketTunnelProvider` managed via `NETunnelProviderManager`

- **Status:** Accepted
- **Context:** Apple's only supported way to capture system-wide traffic
  for a custom VPN on iOS is the `NetworkExtension` framework, specifically
  `NEPacketTunnelProvider` for packet-tunnel-style VPNs. The container app
  installs and controls the VPN configuration via `NETunnelProviderManager`.
- **Decision:** Implement VPN Mode as:
  - a `PacketTunnelProvider` `NetworkExtension` target hosting the Go
    runtime (`OlcRTCMobile.xcframework`) and bridging
    `NEPacketTunnelFlow` to/from the olcRTC client,
  - the SwiftUI container app managing the VPN configuration through
    `NETunnelProviderManager` (install, enable, start, stop, observe
    status),
  - a shared Swift module used by both targets for profile loading,
    settings, and logging.
- **Consequences:**
  - The project will have at least two app targets and one shared module.
  - Runtime on a real iPhone for VPN Mode is gated on Apple signing +
    provisioning + the `NetworkExtension` entitlement (see ADR-0008).
  - The architecture is the "correct" iOS VPN shape, ready to be signed
    later without redesign.

---

## ADR-0005 — Local Proxy Mode is a foreground compatibility / testing mode, not background-safe

- **Status:** Accepted
- **Context:** Running the Go core in the main app process exposes a
  SOCKS / local-proxy endpoint (e.g. `127.0.0.1:8808`) that other apps
  can use. But iOS may suspend a foreground app's process — including
  when a different VPN app is active — so this mode cannot promise
  continuous background availability.
- **Decision:** Ship Local Proxy Mode as an explicit foreground mode for
  compatibility with third-party VPN/proxy apps, manual proxy
  configuration, and testing the Go core. The UI must clearly say it is
  not background-reliable.
- **Consequences:**
  - The UI displays the active local endpoint (e.g. `127.0.0.1:8808`).
  - The UI shows a disclaimer that iOS may suspend the app in the
    background and that VPN Mode is the background-safe option.
  - We do not invest in workarounds that try to keep the foreground
    process alive (background audio tricks, fake location updates, etc.).
    The correct answer is VPN Mode.

---

## ADR-0006 — Background-safe proxy / VPN runtime must live inside the `NetworkExtension` target

- **Status:** Accepted
- **Context:** iOS only guarantees a reliable always-on networking runtime
  inside `NetworkExtension` providers. Anything in the main app process is
  subject to suspension policies.
- **Decision:** Any background-safe runtime (the Go core driving an
  actual tunnel, persistent SOCKS, persistent connections) lives in the
  `PacketTunnelProvider` extension. The main app is a UI / management
  surface plus the foreground-only Local Proxy Mode runtime.
- **Consequences:**
  - The extension owns the Go runtime lifecycle for VPN Mode.
  - The main app starts/stops the extension via
    `NETunnelProviderManager` and communicates with it through the
    documented `NETunnelProviderSession` / App Group channels.
  - Local Proxy Mode is intentionally narrower in scope and does not try
    to be background-safe.

---

## ADR-0007 — Project generator: XcodeGen

- **Status:** Accepted
- **Context:** A no-Mac, CI-only workflow needs a deterministic way to
  produce the `.xcodeproj` (or `.xcworkspace`) consumed by `xcodebuild`.
  The project needs at least two targets (container app +
  `PacketTunnelProvider` extension) plus a shared module, which makes a
  generator more attractive than hand-edited project files.
- **Decision:** Use **XcodeGen**. The generator config lives at
  `ios/OlcRTCClient/project.yml` and is the source of truth for the
  Xcode project. The generated `.xcodeproj` is **not** committed.
- **Rationale:**
  - Simpler than Tuist for an MVP — single YAML file, no Swift DSL
    bootstrap step.
  - `project.yml` is human-reviewable in diffs (a hand-edited
    `project.pbxproj` is not).
  - No need to commit `.xcodeproj` — it is regenerated from
    `project.yml` on every build.
  - Trivial to install on a GitHub Actions macOS runner
    (`brew install xcodegen`).
  - First-class support for an app target plus a
    `NetworkExtension` extension target, with App Group entitlements
    and inter-target dependencies.
- **Consequences:**
  - The repo commits `ios/OlcRTCClient/project.yml` and the Swift
    sources; the generated `.xcodeproj` is gitignored once it exists.
  - Anyone (CI or human) regenerates the project with
    `xcodegen generate` in `ios/OlcRTCClient/`.
  - If we later outgrow XcodeGen (e.g. very complex multi-platform
    targets), a new ADR can supersede this one — but the bar is high
    because migrating away would require regenerating the project
    layout.

---

## ADR-0008 — CI on GitHub Actions macOS runner; unsigned IPA is a CI / later-signing artifact

- **Status:** Accepted
- **Supersedes:** the earlier "unsigned IPA, distribution out of scope"
  framing from the previous revision (which conflicted with the new VPN
  goal).
- **Context:** The user has no Mac. The only viable build host today is
  a macOS GitHub Actions runner. Real-device VPN Mode runtime is a later
  step that needs signing assets we do not have yet.
- **Decision:**
  - All iOS build artifacts are produced by a workflow on `macos-latest`
    (or a pinned macOS image once flakiness forces pinning).
  - The current artifact is an **unsigned** `.ipa`, exposed as a
    workflow artifact. It is explicitly a CI / later-signing artifact —
    suitable for inspection, automated checks, and being signed later.
    It is **not** marketed as a runnable VPN on a stock iPhone.
  - When signing assets become available, a follow-up ADR will describe
    how they are injected (likely via GitHub Actions secrets and a
    separate signed-build job). Today the workflow must not require any
    secret beyond what GitHub provides by default.
  - The CI workflow itself is **not** part of the current step; this ADR
    locks in the target for when it lands.
- **Consequences:**
  - Today: low-friction CI, no Apple ID, no App Store Connect API key,
    no provisioning profiles.
  - Tomorrow: a signed-build pipeline can be added without changing the
    iOS app architecture.

---

## ADR-0009 — Profile / URI / subscription parsing lives in Swift, not Go

- **Status:** Accepted
- **Context:** `docs/uri.md` and `docs/sub.md` describe **client-side
  conventions**. The Go core does not parse `olcrtc://` URIs or
  subscription files. It accepts already-decoded fields via the `mobile`
  API.
- **Decision:** The Swift layer parses `olcrtc://` URIs and subscription
  files in the shared module used by both the container app and the
  `PacketTunnelProvider` extension, then passes individual fields
  (carrier, roomID, clientID, keyHex, transport options, etc.) into the
  gomobile API. No changes to the Go side to "help" with parsing.
- **Consequences:**
  - Swift owns input validation and error messages for malformed URIs
    and subscriptions.
  - If the URI/subscription format evolves, the iOS client must be
    updated in lockstep with `docs/uri.md` and `docs/sub.md`.

---

## ADR-0010 — Log sanitization is enforced before the log line reaches the UI

- **Status:** Accepted
- **Context:** `keyHex`, passwords, and secret-bearing URLs must never
  surface in logs (see hard rules in `CLAUDE.md`). The Go side has its
  own logger; the Swift side hooks into it via `SetLogWriter` from both
  the container app and the extension.
- **Decision:** A shared `LogWriter` implementation, used from both the
  container app and the `PacketTunnelProvider` extension, scrubs
  known-sensitive fields (key material, password fields, raw
  `olcrtc://` strings) before storing or displaying. Sanitization is
  not trusted to upstream code — Swift assumes any incoming line may
  contain a secret and masks defensively.
- **Consequences:**
  - One central place to update masking rules, used by both targets.
  - In-app log view (and any log file written via the App Group) is
    safe to share for bug reports without further redaction.

---

## ADR-0011 — Standalone iOS repo; Go core consumed as `third_party/olcrtc` submodule

- **Status:** Accepted
- **Supersedes:** the implicit assumption in earlier ADRs that the
  iOS sources would live inside `openlibrecommunity/olcrtc` itself.
- **Context:** The iOS client and the Go core have different
  cadences, different test infrastructure (macOS runners vs Linux),
  and different reviewer pools. Pinning iOS work to upstream
  branches creates merge friction and risks accidentally pushing
  iOS-only scaffold changes into upstream. The user has read access
  but not write access to upstream.
- **Decision:**
  - The iOS client lives in its own repository,
    `artpm4250-png/olcrtc-ios`.
  - The Go core is consumed as a **git submodule** at
    `third_party/olcrtc/`, pinned to branch `fix/all` of
    `openlibrecommunity/olcrtc`.
  - The submodule pointer (commit SHA recorded in this repo) is
    the authoritative version of the Go core for this iOS build.
    Bumping the pointer is an explicit commit in this repo.
  - **No Go source edits in this repo.** If the Go core needs a
    change, it happens upstream and we bump the submodule pointer
    here.
- **Rationale:**
  - Clear ownership: iOS sources, GitHub Actions, project memory
    files, and build scripts live where the iOS reviewers are.
  - Upstream stays clean: no iOS-only `.swift`, no XcodeGen yaml,
    no Xcode-specific CI in the Go repo.
  - Reproducible builds: the submodule pointer is a SHA, not a
    floating branch ref, so a checkout always produces the same Go
    core source even if `fix/all` moves.
- **Consequences:**
  - Clone with `--recurse-submodules`, or run
    `git submodule update --init --recursive` after a plain clone.
  - The scaffold-only CI (`ios-scaffold.yml`) does **not** need to
    fetch the submodule — it only builds the SwiftUI app + extension
    stub. When the gomobile build step is added, the future
    `ios-build.yml` workflow will check out submodules.
  - If `fix/all` upstream is force-pushed or deleted, the submodule
    SHA still resolves (Git stores it locally on the runner via
    `actions/checkout`), but `submodule update --remote` will
    diverge — accept that as a future-merge problem, not a today
    problem.
  - When upstream releases changes we want, the explicit workflow
    is:
    1. Upstream: land the Go change on `fix/all`.
    2. Here: `git -C third_party/olcrtc fetch && git -C third_party/olcrtc checkout <sha>`,
       then commit the updated submodule pointer.
    3. Re-run gomobile bind in CI.

---

## ADR-0013 — `OlcRTCMobile` is a static framework wrapper; the `PacketTunnelProvider` extension links it statically (no embed)

- **Status:** Accepted
- **Context:** `gomobile bind -target=ios ./mobile` produces
  `OlcRTCMobile.xcframework` whose per-slice
  `<slice>/OlcRTCMobile.framework/OlcRTCMobile` binary is a
  `current ar archive` — i.e. a `.a`-style **static archive**
  wrapped in a framework directory, not a Mach-O dylib. This is
  gomobile's documented iOS output mode.
  - Probes v2–v9 on branch `packet-tunnel-gomobile-probe` ran the
    extension with the framework as a link-only dependency
    (`embed: false / link: true / codeSign: false`) and tried to
    survive ld_prime's `-dead_strip` via Swift stored properties,
    `-Wl,-u <symbol>`, `-Wl,-needed_framework`, C constructor
    functions, and finally a real `startTunnel` reference. Every
    one of those was stripped from the final extension binary.
  - Probe v10 flipped the extension to `embed: true`. The build
    structurally produced
    `PacketTunnelProvider.appex/Frameworks/OlcRTCMobile.framework`,
    but xcodebuild's embed phase ran
    `builtin-copy -remove-static-executable` against the source
    and emitted `note: Injecting stub binary into codeless
    framework (in target 'PacketTunnelProvider' …)`. The same
    happened for the host app. Both embedded copies ended up as
    ~40 KB codeless dylib stubs with no Mobile symbols.
  - Probe v11 (run
    [26633894897](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26633894897))
    diagnosed the cause: `embed: true` cannot ship a static
    framework, because Xcode's documented embed-phase behaviour
    against a static framework is exactly to strip the static
    executable and replace it with a codeless stub. The host
    app already works because the static archive is **linked**
    into the app's main executable directly — the codeless stub
    framework next to it is inert.
  - Probe v12 (run
    [26634679085](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26634679085),
    classification `PASS-STATIC-LINKED`) acted on that finding:
    revert the extension to `embed: false / link: true /
    codeSign: false` and force-load the device slice's static
    archive into the extension executable. The final
    `PacketTunnelProvider` binary is a 36 MB `Mach-O 64-bit
    executable arm64` that carries every gomobile `Mobile*`
    export (`MobileStart`, `MobileStartWithTransport`,
    `MobileIsRunning`, `MobileSetDebug`, `MobileCheck`,
    `MobilePing`); `nm -u` reports no undefined `Mobile*`
    references; the `.appex/Frameworks/` directory contains no
    `OlcRTCMobile.framework`, and no `.xcframework` leaks into
    the `.app`. `APPLICATION_EXTENSION_API_ONLY = YES` remains
    enabled.
- **Decision:**
  1. **`OlcRTCMobile.xcframework` is treated as a static
     framework wrapper.** No iOS target embeds it as a dynamic
     framework. If a target needs the Go runtime, it links the
     archive into its own executable.
  2. **`PacketTunnelProvider` extension uses
     `embed: false / link: true / codeSign: false`** for the
     `Frameworks/OlcRTCMobile.xcframework` dependency in
     `project.yml`. The extension's `OTHER_LDFLAGS` carries
     `$(inherited) -lresolv -force_load
     $(SRCROOT)/Frameworks/OlcRTCMobile.xcframework/ios-arm64/OlcRTCMobile.framework/OlcRTCMobile`.
     `-force_load` is scoped to that one archive; we deliberately
     do not use `-all_load`.
  3. **`-lresolv` stays on every target that links
     `OlcRTCMobile`.** The Go runtime references the BSD resolver
     symbols `_res_9_n{init,close,search}`, which live in
     `libresolv.tbd` and are not linked by default on iOS.
  4. **`APPLICATION_EXTENSION_API_ONLY = YES` stays enabled on
     `PacketTunnelProvider`.** Any extension-unsafe symbol the
     gomobile runtime might transitively need surfaces at
     compile/link time, not at install-or-runtime.
  5. **Code signing and entitlements stay separate.** ADR-0008
     and the unsigned CI build path are unchanged. The
     `.entitlements` files remain in the repo as a
     future-signing reference, detached from the build until a
     signing identity is configured.
- **Consequences:**
  - The `.appex` executable is large — ~36 MB in probe v12,
    because the Go runtime's object files are now inside it.
    Combined with the host app's existing setup, the final
    `.ipa` will carry the runtime in the app's main executable
    AND in the appex's main executable until the host app is
    cleaned up the same way. That duplication is acceptable for
    Milestone 3 / Milestone 4 work; revisit before any
    App-Store-style size budget applies.
  - `PacketTunnelProvider.appex/Frameworks/OlcRTCMobile.framework`
    must NOT exist after a clean build. The probe workflow
    asserts this; future build pipelines should keep the same
    assertion (or at minimum not regress it).
  - The host app's
    `OlcRTCClient.app/Frameworks/OlcRTCMobile.framework` is
    still a codeless stub (~40 KB) because the host app's
    dependency is still `embed: true`. v12 deliberately does
    not change the host app's shape — the stub is inert
    (nothing dyld-loads it) and removing it is a separate
    follow-up. A future ROADMAP item drops the host-app
    `embed: true` and lets the static archive's link into the
    main app binary stand on its own.
  - Future `PacketTunnelProvider` runtime work (the
    `packet-tunnel-runtime-skeleton` branch, see
    `docs/ROADMAP.md`) calls gomobile APIs from the extension
    directly via the linked-in static archive — there is no
    framework-loading step at runtime, no `dlopen`, no
    `Bundle(forClass:)` indirection. `import OlcRTCMobile`
    resolves through the framework's `Modules/` exposed by the
    `link: true` dependency.
  - This decision does not authorize any VPN runtime,
    `MobileStart*`, `MobileCheck`, `MobilePing`, sockets,
    `NEPacketTunnelNetworkSettings`, or `NEPacketTunnelFlow`
    plumbing in the extension. Those land in their own
    milestones with their own ADRs.

