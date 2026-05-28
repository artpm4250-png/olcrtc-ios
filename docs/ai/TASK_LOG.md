# TASK_LOG.md

Running log for the iOS client track. Append to the appropriate section; do
not rewrite history. The next Claude session reads this to pick up cold, so
write entries that make sense without the surrounding chat.

Date format: `YYYY-MM-DD`. Each entry should answer **what** changed and
**why**, not narrate process.

---

### 2026-05-28 — Initial commit pushed to `artpm4250-png/olcrtc-ios`

- First commit on `main` of the new standalone repo
  (`artpm4250-png/olcrtc-ios`). Contents at this commit:
  - Memory files (`CLAUDE.md`, `docs/ai/PROJECT_MEMORY.md`,
    `docs/ai/DECISIONS.md`, `docs/ai/TASK_LOG.md`) describing the
    standalone-repo identity and the submodule layout
    (`third_party/olcrtc`, branch `fix/all`).
  - iOS scaffold under `ios/OlcRTCClient/` (XcodeGen `project.yml`,
    SwiftUI app, `PacketTunnelProvider` extension, tests).
  - `.github/workflows/ios-scaffold.yml` — scaffold-only CI.
  - `third_party/olcrtc` submodule pinned to `1f1eabc` of `fix/all`.
  - `.gitignore`, `.gitmodules`, `scripts/README.md`, `README.md`.
- `iOS Scaffold Build` workflow triggered via
  `gh workflow run ios-scaffold.yml` against the pushed branch.
  Run URL recorded once the dispatch returns it.
- **Not done in this step**: gomobile bind, Go-side changes,
  workflow-config edits, IPA packaging.

---

### 2026-05-28 — Migrated to standalone repo `artpm4250-png/olcrtc-ios`

- Decision to move the iOS client into its own repository instead of
  living inside upstream `openlibrecommunity/olcrtc`. Reasons recorded
  in **ADR-0011** in `docs/ai/DECISIONS.md`:
  - Upstream has different cadence, different test infrastructure
    (macOS vs Linux runners), and different reviewers.
  - The active GitHub account has read access but not write access
    to upstream, so push and `workflow_dispatch` against
    `openlibrecommunity/olcrtc` are not available.
  - Pinning iOS work into an upstream branch invites merge friction
    and risks pushing iOS-only changes upstream by accident.
- Repository layout in the new repo:
  - `CLAUDE.md`, `README.md` — at root.
  - `docs/ai/` — the three durable memory files
    (`PROJECT_MEMORY.md`, `DECISIONS.md`, `TASK_LOG.md`).
  - `ios/OlcRTCClient/` — XcodeGen `project.yml`, App target,
    PacketTunnelProvider extension target, Tests target — unchanged
    from the previous step.
  - `.github/workflows/ios-scaffold.yml` — unchanged scaffold-only
    CI (does not need the Go core; does not fetch submodules).
  - `scripts/` — placeholder directory with a README. Future
    `ios-bind.sh` (`gomobile bind`) lands here.
  - `third_party/olcrtc/` — **git submodule** added with
    `git submodule add -b fix/all https://github.com/openlibrecommunity/olcrtc.git third_party/olcrtc`.
    Pinned to commit `1f1eabc` of `fix/all` at the time of this
    entry.
  - `.gitignore` — slimmed down for the iOS-only context (Xcode
    noise + generated `.xcodeproj` + future `OlcRTCMobile.xcframework`).
- Memory files updated for the standalone-repo reality:
  - `CLAUDE.md` — rewritten to explicitly identify this repo,
    reference the submodule path, and forbid Go-source edits in
    this repo.
  - `PROJECT_MEMORY.md` — rewritten with the same identity; Go
    source paths now point at `third_party/olcrtc/mobile/...`.
  - `DECISIONS.md` — ADR-0001 updated to reference the submodule
    path; new **ADR-0011** captures the standalone-repo decision
    and the workflow for bumping the submodule pointer.
- **Not done in this step**, intentionally: any code changes to the
  iOS scaffold, the workflow steps, the Go core, or gomobile
  integration. This step is a structural relocation only.

---

## Done

### 2026-05-28 — Project memory files added

- Added `CLAUDE.md` at repo root with the mandatory pre-flight instruction
  pointing at the three docs in `docs/ai/` and the hard rules for the iOS
  track (initial revision — single foreground SOCKS mode).
- Added `docs/ai/PROJECT_MEMORY.md` describing the iOS MVP goal, the
  environmental constraints (no Mac, no Apple Developer account, CI-only
  unsigned IPA), and what is in/out of scope (initial revision — no
  NetworkExtension).
- Added `docs/ai/DECISIONS.md` with the first set of ADRs (reuse Go
  `./mobile` via gomobile, SwiftUI iOS 16+, foreground SOCKS not VPN, CI
  on GitHub Actions producing unsigned IPA, parsing in Swift, log
  sanitization in Swift) and a Proposed ADR for the project generator.
- Added `docs/ai/TASK_LOG.md` (this file) with the initial snapshot.
- No code changes. No Go changes. No GitHub Actions workflow. No iOS
  scaffold.

### 2026-05-28 — Product goal changed to dual-mode VPN + Local Proxy client; memory files rewritten

- Product goal expanded from "foreground SOCKS only" to a **dual-mode
  iOS client**:
  - **VPN Mode** — SwiftUI container app + `NetworkExtension`
    `PacketTunnelProvider` target, managed via
    `NETunnelProviderManager`. Real iOS VPN architecture.
  - **Local Proxy Mode** — foreground local SOCKS / proxy endpoint
    (e.g. `127.0.0.1:8808`) for compatibility with third-party
    VPN/proxy apps, manual proxy configuration, and testing.
- Removed the previous "do not implement VPN" / "not a VPN client"
  framing from `CLAUDE.md` and `PROJECT_MEMORY.md`. New framing:
  **do not fake VPN functionality, do implement real VPN architecture,
  keep unsigned runtime limitations explicit.**
- Made the runtime/architecture distinction explicit:
  - Today CI produces an unsigned IPA as a CI / later-signing artifact.
    We do **not** claim this IPA can install and run VPN on a stock
    iPhone.
  - Real-device VPN Mode runtime is gated on Apple signing +
    provisioning + `NetworkExtension` entitlement.
  - Foreground Local Proxy Mode is not background-reliable on iOS;
    background-safe runtime must live inside the `NetworkExtension`
    target.
- Rewrote `docs/ai/DECISIONS.md` to reflect the new architecture:
  - **Accepted**: ADR-0001 (reuse Go `./mobile` via gomobile, now linked
    into both iOS targets).
  - **Accepted**: ADR-0002 (SwiftUI, iOS 16+ for the container app).
  - **Accepted**: ADR-0003 (dual-mode iOS client) — supersedes the
    earlier "foreground SOCKS, not a VPN" stance.
  - **Accepted**: ADR-0004 (VPN Mode uses `PacketTunnelProvider` +
    `NETunnelProviderManager`).
  - **Accepted**: ADR-0005 (Local Proxy Mode is foreground compatibility
    / testing, not background-safe).
  - **Accepted**: ADR-0006 (background-safe runtime must live inside the
    `NetworkExtension` target).
  - **Proposed**: ADR-0007 (project generator choice — XcodeGen vs
    Tuist).
  - **Accepted**: ADR-0008 (CI on GitHub Actions macOS runner; unsigned
    IPA is a CI / later-signing artifact) — supersedes the earlier
    "distribution out of scope" framing.
  - **Accepted**: ADR-0009 (URI / subscription parsing in Swift,
    shared module used by both targets).
  - **Accepted**: ADR-0010 (log sanitization in Swift, shared module
    used by both targets).
- No code changes. No Go changes. No GitHub Actions workflow added. No
  iOS scaffold created. No `NetworkExtension` target added.

### 2026-05-28 — Accepted ADR-0007 (XcodeGen); iOS scaffold added under `ios/OlcRTCClient/`

- **ADR-0007** flipped from `Proposed` to `Accepted`. Generator =
  **XcodeGen**. Rationale (recorded in `docs/ai/DECISIONS.md`):
  simpler than Tuist for an MVP, `project.yml` is reviewable in
  diffs, no need to commit `.pbxproj`, trivial to install on a
  GitHub Actions macOS runner, first-class support for an app target
  plus a `NetworkExtension` extension target.
- Added the iOS scaffold under `ios/OlcRTCClient/`. Layout:
  - `project.yml` — XcodeGen spec defining three targets:
    `OlcRTCClient` (app), `PacketTunnelProvider` (NetworkExtension),
    `OlcRTCClientTests` (XCUnitTest). Manual signing, `CODE_SIGNING_ALLOWED = NO`
    so CI can build unsigned. Placeholder
    `.entitlements` files for App Group + `packet-tunnel-provider`
    NetworkExtension; both are documented as future-signing
    placeholders.
  - `README.md` — explains what is and is not present, how to
    regenerate the project with `xcodegen generate`, and where
    gomobile will plug in later.
  - `Sources/Shared/Models/` — `ConnectionMode`, `OlcRTCProfile`
    (+ `OlcRTCProvider`, `OlcRTCTransport`), `TunnelStatus`.
  - `Sources/Shared/Services/` — `OlcRTCURIParser` (per
    `docs/uri.md`, jitsi URL roomID supported by splitting on the
    last `#`), `ProfileStore` (JSON in app sandbox today; will
    move to App Group container once signing lands), `LogSanitizer`
    (masks 32+ hex runs, `olcrtc://` URIs, and `keyHex=` /
    `password=` key-value forms).
  - `Sources/App/` — `OlcRTCClientApp` (entry, handles
    `onOpenURL` for `olcrtc://`), `RootView` (TabView:
    Connect / Profiles / Logs / About), `AppState` (mode,
    profile fields, status, log buffer, start/stop/check/ping),
    Views (`ConnectView` with status card + mode picker +
    Start/Stop/Check/Ping + provider/transport pickers +
    room/clientID/keyHex fields with show-hide toggle + Advanced
    disclosure for SOCKS host/port + DNS + debug; `ProfilesView`
    with `ContentUnavailableView` empty state and a basic list;
    `LogsView` with monospaced log, Copy / Clear toolbar;
    `AboutView` with the unsigned-IPA / signing / Local Proxy
    background / NetworkExtension disclaimers;
    `Components/StatusCard`), Services (`VPNManager` — records
    intent today, real `NETunnelProviderManager` wiring deferred;
    `LocalProxyManager` — talks to `MockOlcRTCService` today;
    `MockOlcRTCService` — stand-in for the gomobile bridge).
  - `Sources/PacketTunnelProvider/` — `PacketTunnelProvider`
    subclass of `NEPacketTunnelProvider` whose `startTunnel`
    immediately fails with `notWiredYet`. Real extension target,
    not a fake one — but explicitly does **not** pretend the tunnel
    works. `PacketTunnelConfig` shares the wire schema between the
    app and the extension for the future
    `NETunnelProviderProtocol.providerConfiguration` handoff.
  - `Tests/OlcRTCClientTests/` — `OlcRTCURIParserTests` (wbstream
    examples from `docs/uri.md`, jitsi URL roomID, payload parsing,
    error cases) and `LogSanitizerTests` (hex masking,
    `olcrtc://` masking, key=value masking, pass-through for safe
    lines, short-hex pass-through).
- `.gitignore` updated to ignore the generated `.xcodeproj` /
  `.xcworkspace` / DerivedData / `OlcRTCMobile.xcframework` under
  `ios/`. `project.yml` is the committed source of truth.
- TODOs left in code where gomobile will land: `VPNManager`,
  `LocalProxyManager`, `MockOlcRTCService`, `PacketTunnelProvider`.
  Open question recorded in `README.md` and in
  `PacketTunnelProvider.swift`: whether the same xcframework slice
  can be embedded into both the app and the extension under
  `APPLICATION_EXTENSION_API_ONLY = YES` — must be verified once
  CI actually builds the framework.
- **Not done in this step**, intentionally: gomobile integration,
  GitHub Actions workflow, Go-side changes, real
  `NETunnelProviderManager` wiring, real entitlement values.

### 2026-05-28 — Scaffold-only CI workflow added; entitlements detached from current configs

- Added `.github/workflows/ios-scaffold.yml` (`name: iOS Scaffold
  Build`). Triggers: `workflow_dispatch` and `push` filtered to
  `ios/OlcRTCClient/**`, `docs/ai/**`, and the workflow file itself.
  Runner: `macos-latest`. Steps, in order:
  1. `actions/checkout@v4`.
  2. `xcodebuild -version`.
  3. `brew install xcodegen`.
  4. `cd ios/OlcRTCClient && xcodegen generate`.
  5. `xcodebuild -list -project ios/OlcRTCClient/OlcRTCClient.xcodeproj`.
  6. Build the `OlcRTCClient` scheme for `iphonesimulator` (Debug,
     destination `iPhone 16`), unsigned (`CODE_SIGNING_ALLOWED=NO`).
  7. Run tests on the same simulator destination.
  8. Build the same scheme for `iphoneos` (Release, generic
     destination), unsigned.
- **Entitlements made conditional.** The previous revision attached
  `Sources/App/OlcRTCClient.entitlements` and
  `Sources/PacketTunnelProvider/PacketTunnelProvider.entitlements`
  via `CODE_SIGN_ENTITLEMENTS` in `project.yml`. That breaks an
  unsigned build because
  `com.apple.developer.networking.networkextension` requires a
  matching provisioning profile, which we deliberately do not have
  (ADR-0008). Fix:
  - Removed both `CODE_SIGN_ENTITLEMENTS` entries from `project.yml`.
  - Kept both `.entitlements` files in the repo as a future-signing
    reference; updated their XML comments and the package
    `README.md` to make their detached status explicit. They are
    reattached by uncommenting one line in `project.yml` when a
    signing identity becomes available.
  - Did **not** remove the VPN architecture, the `PacketTunnelProvider`
    target, the App Group bundle IDs, or the `NetworkExtension` import
    in the provider. The architecture stays ready for signing.
- Other small cleanups to `project.yml`:
  - Dropped two stray `INFOPLIST_KEY_*_Generation` settings (Xcode
    generator-only flags, not actual build settings) and an empty
    `SWIFT_OBJC_BRIDGING_HEADER`.
  - Kept `APPLICATION_EXTENSION_API_ONLY: YES` on the
    `PacketTunnelProvider` target so the extension will surface any
    misuse of app-only APIs the moment it actually builds in CI.
  - Kept iOS deployment target at 16.0 across all three targets.
  - Kept the app's embed-extension dependency
    (`embed: true, codeSign: false`) so the extension binary ends up
    inside the `.app` bundle.
- **Not done in this step**, intentionally: gomobile build script,
  `OlcRTCMobile.xcframework` integration, Go-side changes, unsigned
  `.ipa` packaging, signed builds, real `NETunnelProviderManager`
  wiring.

---

## Broken / known issues

- Nothing observed broken yet. The new workflow has not been triggered
  at the time of writing. Plausible failure modes the next session
  should be ready for once the workflow runs the first time:
  - **Simulator name drift.** `iPhone 16` is the explicit destination
    in the workflow per the task brief, but the `macos-latest` image
    might pin a different roster. If the destination is rejected
    (`xcodebuild: error: Unable to find a destination matching ...`),
    fall back to `name=iPhone 15` or use `OS=latest` with whatever
    runtime ships on `macos-latest`.
  - **`brew install xcodegen` cache pressure.** If `brew` is slow or
    flaky on `macos-latest`, switch to the prebuilt
    `mxcl/homebrew-bundle` or a pinned `xcodegen` release.
  - **`APPLICATION_EXTENSION_API_ONLY: YES` symbol bans.** The shared
    `Sources/Shared/` directory compiles into the extension target as
    well. If any of those files (or anything they import) uses a
    symbol marked unavailable for app extensions, the extension build
    will fail. The fix is to gate the use behind
    `#if !APPLICATION_EXTENSION_API_ONLY` or to split the file out of
    the extension's sources.
  - **`embed: true, codeSign: false` on extensions.** Newer XcodeGen
    versions are picky; if the dependency syntax is rejected, switch
    to `codeSignOnCopy: false` or use the longer form.
  - **Unsigned-build warnings.** `xcodebuild` will print warnings
    about missing signing identities even with
    `CODE_SIGNING_ALLOWED=NO`. Warnings are fine; only fail on
    errors.

---

## Next

Ordered by intended sequence. Each item should be a separate change /
session so the diff stays reviewable.

1. **Trigger and stabilize `iOS Scaffold Build`.** Push the scaffold +
   workflow, watch the first run, fix whatever the macOS runner
   complains about (simulator destination, XcodeGen version, etc.),
   record the green run URL in this file. **Do not** move to gomobile
   until this is green.
2. **Add the gomobile build step.** Script (likely
   `script/ios-bind.sh` or equivalent) that runs
   `gomobile bind -target=ios ./mobile` and places
   `OlcRTCMobile.xcframework` where both iOS targets consume it
   (most likely `ios/OlcRTCClient/Frameworks/`). Document the
   required Go and gomobile versions.
3. **Wire the xcframework into both iOS targets.** Update
   `project.yml` to add the framework as a dependency for
   `OlcRTCClient` and `PacketTunnelProvider`. Replace
   `MockOlcRTCService` calls in `LocalProxyManager` with the real
   gomobile bridge. The scaffold workflow gets a sibling workflow
   (`ios-build.yml`) that runs the gomobile bind before
   `xcodegen generate`.
4. **Profile store in App Group container.** Move `ProfileStore` from
   the app sandbox to the shared App Group so the extension can read
   profiles. Decide whether `keyHex` moves to Keychain — write a new
   ADR before coding. Re-attaching the entitlements happens here
   only if a signing identity is available; otherwise the App Group
   path stays "future-signing".
5. **Subscription import** per `docs/sub.md`. HTTPS fetch + parse
   + merge into the shared profile store.
6. **Local Proxy Mode end-to-end.** Replace the stub call path with
   the real gomobile `Start` / `Stop` / `Check` / `Ping`. SOCKS
   endpoint display already wired; just feed real values through.
7. **VPN Mode plumbing.** Real `NETunnelProviderManager` install /
   enable / observe in `VPNManager`. In the extension, configure
   `NEPacketTunnelNetworkSettings`, bring up the Go runtime against
   the selected `PacketTunnelConfig`, bridge `NEPacketTunnelFlow`.
   Real-device runtime is still gated on signing — that is fine for
   this step.
8. **Sanitized log view in-extension.** Currently `LogSanitizer` is
   compiled into both targets but only the app exposes a UI. Once
   the extension produces real logs, mirror them into the App
   Group so the app UI can show them.
9. **Unsigned `.ipa` packaging step.** Once gomobile is wired,
   extend the build workflow to package an unsigned `.ipa` and
   upload it as a workflow artifact (ADR-0008).
10. **(Future, gated on signing)** A separate signed-build pipeline
    once an Apple Developer account, provisioning profile, and
    `NetworkExtension` entitlement are available. New ADR before
    any code lands. Reattaching the `.entitlements` files happens
    here.

Do not skip ahead — earlier steps unblock later ones, and the
constraints in `CLAUDE.md` will reject shortcuts that try to.
