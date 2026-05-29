# Roadmap — olcrtc-ios

Sequenced milestones for the standalone iOS client. Each milestone is
a separate, reviewable chunk of work; earlier milestones unblock later
ones, and the constraints in
[`../CLAUDE.md`](../CLAUDE.md) will reject shortcuts that try to skip
ahead.

This roadmap is the high-level companion to
[`ai/TASK_LOG.md`](ai/TASK_LOG.md) (low-level, append-only,
session-by-session record) and
[`ai/DECISIONS.md`](ai/DECISIONS.md) (ADRs). When a milestone
ships, append a `done` line under its acceptance criteria — do not
rewrite the roadmap entry; new decisions get a new ADR.

---

## Milestone 1 — Local Proxy MVP

**Status:** mostly complete (`2026-05-28`).

**Goal:** the user can open the app, fill or import an olcRTC
profile, hit **Start** in Local Proxy Mode, and route a third-party
app's traffic through the resulting local SOCKS endpoint. Logs are
sanitized. The full pipeline (`gomobile bind` → XcodeGen → Debug
simulator + tests → Release `iphoneos` → unsigned IPA → structural
validation) runs green on every CI push.

**Tasks:**
- [x] Standalone iOS repo with the upstream Go core as
      `third_party/olcrtc` submodule (ADR-0011).
- [x] `gomobile bind ./mobile` builds `OlcRTCMobile.xcframework`
      reproducibly on `macos-latest` (`scripts/build-gomobile-ios.sh`).
- [x] XcodeGen `project.yml` with `OlcRTCClient` app target +
      `PacketTunnelProvider` extension target + `OlcRTCClientTests`.
- [x] `iOS App + Gomobile Build` workflow green end-to-end.
- [x] Unsigned IPA packaging + structural validation.
- [x] Local Proxy Mode wired to the real gomobile API
      (`Start` / `Stop` / `Check` / `Ping` / `IsRunning` /
      `WaitReady` / `SetLogWriter`).
- [x] `LogSanitizer` masks 32+ hex runs, `olcrtc://` URIs, and
      `keyHex=` / `password=` style key/value pairs.
- [x] `ProfileValidator` blocks **Start** on invalid profiles;
      inline errors in Connect UI.
- [x] URI parser is strict about scheme, provider, transport, and
      enforces 64 hex chars for `keyHex`; percent-decodes room +
      MIMO; uses MIMO as default profile name.
- [x] Subscription importer: HTTP/HTTPS, per-line parse, skipped
      lines logged with structured reasons (no raw line, no key).
- [x] Profiles tab: tap-to-load, swipe-to-delete, URI import sheet,
      subscription import sheet, dedup on
      (provider, transport, room, key, clientID).
- [x] `RELEASE_CHECKLIST.md` and `ROADMAP.md` (this file).

**Open follow-ups inside Milestone 1** (small, can land before
Milestone 2 starts):
- [ ] Manual QA on a real iPhone — gated on a signing identity.
      Re-run §3 of `RELEASE_CHECKLIST.md` and capture findings.
- [ ] Consider moving `ProfileStore` JSON into the App Group
      container so `PacketTunnelProvider` can read it (a no-op
      change today because the extension is stubbed; required by
      Milestone 3 / 4).
- [ ] Decide whether `keyHex` moves to the Keychain — write a new
      ADR before coding (currently it lives in the JSON file).

**Blockers:** none for the green-CI portion. The manual-QA portion
is blocked on a paid Apple Developer account + a Mac with Xcode.

**Acceptance criteria:**
- `iOS App + Gomobile Build` workflow runs green from a fresh
  checkout with no local edits.
- `OlcRTCClient-unsigned-ipa` artifact is produced, validated, and
  uploaded automatically.
- Every CI check listed in `RELEASE_CHECKLIST.md` §2 is green.
- Every privacy check listed in `RELEASE_CHECKLIST.md` §4 has an
  enforcing automated test that runs in CI.

---

## Milestone 2 — Real-device signed build

**Status:** not started. Blocked on resources, not on code.

**Goal:** turn the unsigned IPA into an artifact that can actually
install and run on a real iPhone owned by the project owners (or by
a tester). VPN Mode runtime is **not** wired yet — this milestone is
about signing the existing scaffold, not about implementing VPN
Mode.

**Tasks:**
- [ ] Acquire a paid Apple Developer account ($99/year).
- [ ] Create an App ID for `org.openlibrecommunity.olcrtc.client`
      and a matching App ID for
      `org.openlibrecommunity.olcrtc.client.PacketTunnelProvider`.
- [ ] Provision a development team certificate + a development
      provisioning profile scoped to both App IDs, with the
      `com.apple.developer.networking.networkextension` entitlement
      enabled on the extension App ID.
- [ ] Add a `signed-build` workflow (separate from
      `iOS App + Gomobile Build` to keep the unsigned path simple)
      that consumes the existing unsigned IPA (or re-builds with
      signing enabled) and produces a signed `.ipa`. Secrets stored
      as GitHub Actions encrypted secrets, never logged.
- [ ] Re-attach `Sources/App/OlcRTCClient.entitlements` and
      `Sources/PacketTunnelProvider/PacketTunnelProvider.entitlements`
      via `CODE_SIGN_ENTITLEMENTS` in `project.yml` **only in the
      signed build path** (the unsigned path keeps them detached
      per ADR-0008).
- [ ] Manual sideload onto a real iPhone (Xcode → Window → Devices,
      or `ideviceinstaller` from a Mac).
- [ ] Walk the manual QA checklist in §3 of
      `RELEASE_CHECKLIST.md`.

**Blockers:**
- Paid Apple Developer account.
- A Mac with Xcode (or a remote macOS CI runner with the signing
  identity loaded into the keychain at job time).
- A physical iPhone the team owns to sideload onto.

**Acceptance criteria:**
- A signed `.ipa` installs on a real iPhone without "Untrusted
  Developer" friction (after the team trusts the dev certificate
  once).
- The Local Proxy Mode flow from Milestone 1 still works on the
  signed build.
- VPN Mode still fails fast with `notWiredYet` — that's expected at
  this milestone; Milestone 3 fixes it.

---

## Milestone 3 — PacketTunnelProvider / gomobile feasibility probe

**Status:** **build/link probe complete** on branch
`packet-tunnel-gomobile-probe`. Probe v12 (run
[26634679085](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26634679085))
classification `PASS-STATIC-LINKED`. The static-link
architecture is locked in by [ADR-0013](ai/DECISIONS.md). The
runtime / on-device portion of this milestone (real `startTunnel`
wiring, memory-budget stress) still depends on Milestone 2 and
the next implementation milestone (`packet-tunnel-runtime-skeleton`,
below).

The probe-only source/build mutations on
`packet-tunnel-gomobile-probe` (extension `OTHER_LDFLAGS`
force-load, framework dependency, `LLVM_LTO`,
`GomobileExtensionProbe.swift`) were **reverted as part of the
merge-safety cleanup** so the branch can merge into `main` without
breaking `iOS Scaffold Build` or `iOS App + Gomobile Build`. The
probe workflow
(`.github/workflows/packet-tunnel-gomobile-probe.yml`) is now
`workflow_dispatch`-only and is preserved as a research /
archival recipe. Reintroducing the static-link settings on the
runtime branch (`packet-tunnel-runtime-skeleton`) is part of
Milestone 3.5 — see the notes there.

**Goal:** verify that `OlcRTCMobile.xcframework` can be linked into
the `PacketTunnelProvider` extension target under
`APPLICATION_EXTENSION_API_ONLY = YES`, and that the extension
process can host the Go runtime without being killed by the iOS
extension memory budget.

**Tasks:**
- [x] Add `Frameworks/OlcRTCMobile.xcframework` as a framework
      dependency on the extension target in `project.yml`. Probes
      v2–v9 ran with `embed: false, codeSign: false, link: true`
      (the host app already owns the embedded copy; the extension
      only needs the link edge for symbol resolution), but every
      one of them ended with ld_prime's `-dead_strip` removing
      `LC_LOAD_DYLIB` for `OlcRTCMobile` from the final extension
      binary regardless of which anchor strategy held the symbol
      reference. Probe v10 flipped to `embed: true, codeSign:
      false, link: true` so XcodeGen emitted a Copy Files (Embed
      Frameworks) phase, but xcodebuild's embed phase ran
      `builtin-copy -remove-static-executable` against the source
      and injected a 40 KB codeless stub into both
      `OlcRTCClient.app/Frameworks/` and
      `PacketTunnelProvider.appex/Frameworks/` — no Mobile
      symbols shipped in either copy. Probe v11 (run
      [26633894897](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26633894897))
      diagnosed why: gomobile's `.framework/<name>` binary is a
      `current ar archive` — a static archive wrapped in a
      framework directory, **not** a Mach-O dylib — and Xcode's
      embed phase strips static-archive frameworks by design.
      Probe v12 acts on that finding: revert the extension to
      `embed: false, link: true, codeSign: false` and link the
      static archive into the extension binary directly via
      `OTHER_LDFLAGS: $(inherited) -lresolv -force_load
      $(SRCROOT)/Frameworks/OlcRTCMobile.xcframework/ios-arm64/OlcRTCMobile.framework/OlcRTCMobile`.
      This mirrors how the host app already gets the Go runtime.
      See `docs/ai/TASK_LOG.md` for the v2–v12 probe chain. Branch
      `packet-tunnel-gomobile-probe`.
- [x] Mirror `OTHER_LDFLAGS: $(inherited) -lresolv` from the host
      app onto the extension target (the Go runtime needs BSD
      resolver symbols regardless of which target hosts it).
- [x] Add `Sources/PacketTunnelProvider/GomobileExtensionProbe.swift`
      that references `MobileIsRunning()` and
      `MobileSetDebug(false)` so the linker actually pulls in
      OlcRTCMobile symbols. The probe is **never called from
      `startTunnel`** — its only job is to force the link edge.
- [x] Add `.github/workflows/packet-tunnel-gomobile-probe.yml`
      that runs gomobile bind → XcodeGen → unsigned Release
      `iphoneos` build of the host scheme (which depends on the
      extension target), then `otool -L` / `nm -u | grep Mobile`
      to surface the extension's link footprint. No IPA packaged,
      no app tests run.
- [ ] Audit the gomobile-generated headers for any symbol marked
      unavailable to app extensions. If anything trips, isolate it
      behind a thin shim that the extension links against (the
      shim can call the real symbol from the app side, never from
      the extension side).
- [ ] Make a minimal `PacketTunnelProvider.startTunnel(options:)`
      that:
      - reads `NETunnelProviderProtocol.providerConfiguration`
        decoded as `PacketTunnelConfig`;
      - calls `MobileSetProviders` / `MobileSetTransport` /
        `MobileStartWithTransport` with the config;
      - returns the completion handler once
        `MobileWaitReady(timeoutMillis:)` resolves;
      - logs to a shared App Group log file (so the main app's
        Logs tab can mirror it).
- [ ] Smoke test the binary size of the signed `.ipa`. Probe v10
      moved the extension to `embed: true`, which would have
      duplicated `OlcRTCMobile.framework` (~33 MB) into both the
      app and the appex; v11 found the embed phase stripped both
      copies to 40 KB stubs. Probe v12 reverts the extension to
      `embed: false` and links the static archive into the
      extension executable instead — the Go runtime's object
      files end up inside `PacketTunnelProvider`'s own binary
      (mirroring how the host app's main binary already carries
      the same archive). The host app keeps its own
      `embed: true / codeless-stub` framework for now (v12
      doesn't change the host app), so the `.ipa` will still
      contain the host app's stub `Frameworks/OlcRTCMobile.framework`
      directory plus two executables that each carry a copy of
      the Go runtime. A future optimization could share the
      runtime via a true dynamic framework once gomobile gains
      that mode, or split the Go core into a smaller leaf the
      extension can link without doubling app size.
- [ ] Stress test the extension memory budget (~15 MB on older
      devices, ~50 MB on newer). Capture peak RSS in `Logs`.

**Blockers:**
- The build/link probe (first three tasks) is **not blocked**: it
  runs entirely from CI on `macos-latest`, unsigned. That's the
  current `packet-tunnel-gomobile-probe` branch.
- The runtime tasks (everything below the third `[ ]`) are still
  blocked on Milestone 2 (signed build on a real iPhone).
- Possibly an upstream Go-core change if `APPLICATION_EXTENSION_API_ONLY`
  rejects a symbol — Go-core changes go through the upstream repo
  (ADR-0011), not this one.

**Acceptance criteria:**
- The extension target links cleanly with
  `APPLICATION_EXTENSION_API_ONLY = YES` and the gomobile static
  archive force-loaded into the extension executable (probe v12
  classification `PASS-STATIC-LINKED`). **Met** by run
  [26634679085](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26634679085).
- `startTunnel` runs to completion against a real olcRTC endpoint
  and `NEPacketTunnelFlow.readPackets` starts producing data.
- The extension process stays under the iOS memory budget for a
  10-minute session.
- The main app's Logs tab shows extension log lines via the App
  Group log file, with sanitization preserved end-to-end.

---

## Milestone 3.5 — `packet-tunnel-runtime-skeleton`

**Status:** **done** (`2026-05-29`, [PR #1](https://github.com/artpm4250-png/olcrtc-ios/pull/1)).
All acceptance criteria met under the unsigned CI path. Direct
successor to Milestone 3; consumes [ADR-0013](ai/DECISIONS.md).
One non-blocking follow-up — workflow-level assertions of the
v12 contract — is recorded under "Open follow-ups" below; the
contract still holds implicitly through the project.yml
settings.

**Goal:** wire the lifecycle skeleton between the host app and the
`PacketTunnelProvider` extension *without* starting any olcRTC
network runtime. The extension will start and stop cleanly, read
the selected profile from a shared config surface, and write its
own logs — all without calling `MobileStart*` / `MobileCheck` /
`MobilePing`. This is the last unsigned-CI step before signed-device
work in Milestone 4.

**Branch:** `packet-tunnel-runtime-skeleton`.

**Tasks:**
- [x] Reintroduce the static-link settings on the
      `PacketTunnelProvider` target that the probe branch
      reverted in its merge-safety cleanup. The v12 form
      hard-coded `ios-arm64/` in `OTHER_LDFLAGS` and broke
      `iOS App + Gomobile Build` for the simulator slice. The
      runtime branch must use sdk-specific paths — either
      per-config `OTHER_LDFLAGS[sdk=iphoneos*]` /
      `OTHER_LDFLAGS[sdk=iphonesimulator*]`, or a build setting
      indirection that resolves to the correct slice
      (`ios-arm64` for iphoneos, `ios-arm64_x86_64-simulator`
      for the simulator). Re-add the
      `Frameworks/OlcRTCMobile.xcframework` extension
      dependency (`embed: false / link: true / codeSign: false`)
      and the `-lresolv` flag. Re-add a small Swift / Obj-C
      anchor file (the v12 `GomobileExtensionProbe.swift`
      pattern) so `import OlcRTCMobile` resolves in the
      extension. CI workflows that exercise this branch must
      run `gomobile bind` before `xcodebuild` and check out
      submodules.
      *Done in stage 1 (commit `aa9effe`) using sdk-aware
      `OTHER_LDFLAGS[sdk=iphoneos*]` / `[sdk=iphonesimulator*]`.*
- [x] Define the shared config surface between the app and the
      extension. Likely shape: app writes the selected
      `PacketTunnelConfig` into the App Group container (or
      Keychain for `keyHex`, per ADR-0010 follow-up) and the
      extension reads it from the same container during
      `startTunnel`. No new entitlements yet — App Group
      attachment lands when signing does.
      *Done in stage 2 (commit `98773e0`):
      `Sources/Shared/Services/SharedConfigStore.swift` writes
      JSON to `<container>/packet-tunnel-config.json`;
      entitlements remain declared-but-detached per ADR-0008.*
- [x] Extend `PacketTunnelProvider.startTunnel(options:)` to:
      read the selected profile from the shared surface; validate
      it; log the resolved (sanitized) profile fields; return
      `notWiredYet` after logging. **No** `MobileStart*` /
      `MobileCheck` / `MobilePing`. **No** sockets. **No**
      `NEPacketTunnelNetworkSettings.setTunnelNetworkSettings`.
      *Done in stage 1 (decode from `providerConfiguration`) and
      stage 2 (fallback to `SharedConfigStore.load()`). Hard
      scope kept: `MobileSetDebug(false)` + `MobileIsRunning()`
      via `GomobileExtensionProbe.touchNonStartingAPI()` only.*
- [x] Implement `PacketTunnelProvider.stopTunnel(with:completionHandler:)`
      — clean teardown of any state the skeleton allocates (none
      yet from gomobile; just lifecycle scaffolding).
      *Done in stage 1: symmetric, idempotent, sanitized log of
      reason code.*
- [x] Mirror sanitized extension logs into the App Group so the
      main app's Logs tab can show them end-to-end. Reuse the
      existing `LogSanitizer` (ADR-0010) — no new sanitization
      paths.
      *Done in stages 2 + 3:
      `Sources/Shared/Services/SharedLogStore.swift` provides
      the append-only file (head-truncated at 64 KiB);
      `PacketTunnelProvider.logSanitized` mirrors every line
      through it; `AppState.mirrorExtensionLogs()` pulls and
      content-dedupes into `logLines`; `LogsView.onAppear` and
      `.refreshable` trigger the pull. Unit tests cover both
      stores under temp-dir URLs.*
- [ ] Update the probe / build workflows to keep asserting the
      v12 contract: gomobile static archive is linked into the
      `.appex` executable; no `OlcRTCMobile.framework` directory
      inside `.appex/Frameworks`; no `.xcframework` leak;
      `APPLICATION_EXTENSION_API_ONLY = YES` stays.
      *Deferred — non-blocking. The contract still holds
      implicitly via the project.yml settings (no embed phase
      is emitted, `-force_load` pulls the archive, API-only flag
      stays). Hardening this into explicit CI assertions is a
      small follow-up that does not gate Milestone 4 — see the
      "Open follow-ups" item below.*

**Blockers:**
- None for the skeleton itself — the architecture is locked in by
  ADR-0013, the static link works under unsigned CI, and the
  shared-surface read/write is plain Foundation work.
- Anything that calls into gomobile starter functions or actually
  brings up a tunnel still requires the signed-device path
  (Milestone 2 → Milestone 4).

**Acceptance criteria:**
- The host app writes the selected `PacketTunnelConfig` into a
  shared surface that survives across the app/extension boundary.
- `PacketTunnelProvider` reads that config in `startTunnel`,
  validates it, sanitized-logs the result, and returns the
  existing `notWiredYet` failure. The extension does not start
  any olcRTC network runtime.
- `PacketTunnelProvider.stopTunnel` is symmetric and idempotent
  for whatever state the skeleton holds.
- No secrets land in any log sink (App Group log file or
  in-app Logs tab) — covered by `LogSanitizer` / `LogSanitizerTests`.
- The unsigned CI pipelines stay green; the v12 contract
  (`PASS-STATIC-LINKED`, no embedded framework, no `.xcframework`
  leak, `APPLICATION_EXTENSION_API_ONLY = YES`) keeps passing.
- The signed-device runtime requirement remains documented in
  [ADR-0008](ai/DECISIONS.md) and Milestone 4 — this milestone
  does not unblock VPN runtime, only the lifecycle skeleton.

**Open follow-ups inside Milestone 3.5** (small, do not gate
Milestone 4):
- [ ] Fold the v12 contract assertions (no embedded
      `OlcRTCMobile.framework` inside `.appex/Frameworks`, no
      `.xcframework` leak, `nm -gU` shows `Mobile*` exports in
      the `.appex` executable, `APPLICATION_EXTENSION_API_ONLY = YES`)
      into `iOS App + Gomobile Build` after the build step, so a
      future regression is caught loudly rather than relying on
      the project.yml comments alone. Pattern lives in the
      `packet-tunnel-gomobile-probe.yml` classifier — adapt and
      promote, do not duplicate.

**Done (2026-05-29, [PR #1](https://github.com/artpm4250-png/olcrtc-ios/pull/1)):**
all acceptance criteria above are met under the unsigned CI
path. Per-stage narrative lives in
[`docs/ai/TASK_LOG.md`](ai/TASK_LOG.md) under the four
Milestone 3.5 entries dated `2026-05-29`.

---

## Milestone 4 — Background-safe VPN runtime

**Status:** not started. **Code-side prerequisites complete**
(Milestone 3.5 done in [PR #1](https://github.com/artpm4250-png/olcrtc-ios/pull/1)).
Now **resource-blocked** on a paid Apple Developer account +
signing identity (Milestone 2), not code-blocked. When signing
lands, attaching `CODE_SIGN_ENTITLEMENTS` on both targets
(exact lines documented in `ios/OlcRTCClient/project.yml`)
plus the Milestone 4 task list below is the path to a working
device tunnel.

**Goal:** ship VPN Mode as a real iOS VPN. The user enables it from
**Connect**, iOS pops the standard system VPN consent sheet, the
tunnel comes up via `NETunnelProviderManager.startVPNTunnel`, and
stays up across app suspend/resume.

**Tasks:**
- [ ] Implement `VPNManager.start(profile:)` using
      `NETunnelProviderManager.loadAllFromPreferences` +
      `saveToPreferences` + `startVPNTunnel`. Encode the selected
      profile into `NETunnelProviderProtocol.providerConfiguration`
      as `PacketTunnelConfig`.
- [ ] Implement `PacketTunnelProvider.startTunnel` to configure
      `NEPacketTunnelNetworkSettings` (IPv4/IPv6 addresses, DNS,
      routes) and drive the Go runtime to bridge
      `NEPacketTunnelFlow` ↔ olcRTC transport.
- [ ] Implement `stopTunnel(with:)` reason handling.
- [ ] On-demand rules / connect-on-launch (optional — decide
      before coding).
- [ ] Observe `NEVPNStatusDidChange` in the app and reflect into
      `TunnelStatus`.
- [ ] Move `ProfileStore` JSON to the App Group container (if not
      done as a Milestone 1 follow-up) so the extension can read
      profiles without an IPC round trip on every restart.

**Blockers:**
- Milestone 3 (feasibility confirmed).
- Possible upstream Go-core changes to support packet-flow handoff
  if `./mobile` doesn't already expose a streaming-bytes API.

**Acceptance criteria:**
- VPN Mode actually tunnels traffic on a real iPhone for the
  duration of a typical browsing session, including after the app
  is backgrounded for >10 minutes.
- Killing the app does not kill the tunnel (the extension owns
  the runtime).
- `On Demand` (if implemented) reconnects automatically after a
  network change.
- Logs remain sanitized end-to-end.

---

## Milestone 5 — Distribution strategy

**Status:** not started. Independent decision; can be planned in
parallel with Milestone 4 once Milestone 3 confirms the runtime is
viable.

**Goal:** decide and execute on how end users get the signed app.
This is an explicit decision, not a default — App Store, TestFlight,
ad-hoc enterprise, and Sideloadly are all real options with very
different costs.

**Tasks:**
- [ ] Write a new ADR (e.g. ADR-0012) recording the decision and
      why. Inputs to the decision:
      - whether the team has access to enterprise distribution;
      - whether App Store review will accept the
        `NetworkExtension` entitlement for this use case;
      - whether TestFlight's 100-tester / 90-day cycle fits the
        target audience;
      - whether ad-hoc UDID provisioning is acceptable.
- [ ] Whichever channel is chosen, set up the corresponding CI
      pipeline (a separate workflow). For App Store / TestFlight:
      `xcrun altool` or `fastlane` with notarized credentials in
      GitHub Secrets.
- [ ] Update `README.md` and `RELEASE_CHECKLIST.md` to point at
      the new distribution path; remove the "unsigned IPA only"
      language once the chosen channel is live.
- [ ] Capture a privacy nutrition label (App Store privacy
      questionnaire) that matches what the app actually does:
      no analytics, no third-party SDKs, on-device profile storage,
      no telemetry to any server other than the user-configured
      olcRTC endpoint.

**Blockers:**
- Milestone 4 (real VPN runtime is needed for App Store
  submission to be honest).
- Apple Developer account in good standing.

**Acceptance criteria:**
- End users have a documented, repeatable way to install the
  latest signed build without needing the team's signing keys.
- The chosen channel is reflected in `README.md` + a top-level
  link from the GitHub Actions Summary tab.
- The next release artifact is produced by the new pipeline, not
  by the unsigned `iOS App + Gomobile Build` workflow.
