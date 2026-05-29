# Release checklist — olcrtc-ios

Pre-release hardening checklist for the standalone `artpm4250-png/olcrtc-ios`
iOS client. This is the source of truth for what "release-ready" means
at the **current** stage (Local Proxy MVP, unsigned IPA, VPN Mode stubbed)
and what remains gated on later milestones (see
[`ROADMAP.md`](ROADMAP.md)).

The checklist is meant to be walked top-to-bottom before each
milestone artifact is handed off to whoever does the next step. Items
that require a Mac / a signed build / a real iPhone are marked as
such — they are **out of scope today** but listed so they don't get
forgotten when a signing identity becomes available.

## 1. Current artifact

- **Workflow:** [`iOS App + Gomobile Build`](../.github/workflows/ios-app-gomobile.yml)
  on `macos-latest`.
- **Artifact name:** `OlcRTCClient-unsigned-ipa`.
- **Archive path inside the run:** `build/ipa/OlcRTCClient-unsigned.ipa`.
- **What it is:** Release `iphoneos` `.app` zipped into the standard
  `Payload/OlcRTCClient.app/...` IPA layout. Contains the main app
  binary, the embedded `Frameworks/OlcRTCMobile.framework` (gomobile
  bind of the upstream Go core), and the embedded
  `PlugIns/PacketTunnelProvider.appex`.
- **What it is NOT:** a signed, installable, runnable iOS app. The
  archive has no `_CodeSignature/`, no embedded provisioning
  profile, no `NetworkExtension` entitlement. iOS will refuse to
  install it on a stock iPhone. It is meant to be consumed by a
  later signed-build pipeline that re-signs and re-packages it.

## 2. CI checks (every push to the relevant paths runs all of these)

Each check is a step in the `iOS App + Gomobile Build` workflow.
A workflow run that goes green has passed every item below.

| # | Check | Step name | What it verifies |
|---|---|---|---|
| 1 | gomobile bind | `Build OlcRTCMobile.xcframework` | Upstream Go core (`third_party/olcrtc/mobile`) builds an iOS xcframework via `gomobile bind`. |
| 2 | XcodeGen project generation | `Generate Xcode project` | `project.yml` produces a valid `.xcodeproj` on the runner. |
| 3 | Simulator build | `Build app (unsigned, Debug, iphonesimulator)` | App + extension + tests compile clean for Debug on the iOS Simulator. |
| 4 | Unit tests | `Run tests (iphonesimulator)` | `OlcRTCURIParserTests`, `ProfileValidatorTests`, `SubscriptionImporterTests`, `LogSanitizerTests` all pass. |
| 5 | Release iphoneos build | `Build app (unsigned, Release, iphoneos generic)` | App + extension compile clean for Release `iphoneos` unsigned. |
| 6 | IPA packaging | `Package unsigned IPA` | The Release `.app` is wrapped into `Payload/OlcRTCClient.app/...` and zipped to `build/ipa/OlcRTCClient-unsigned.ipa`. |
| 7 | IPA structure validation | `Inspect and validate unsigned IPA structure` | The freshly-built IPA is unzipped and asserted to contain every required path (app bundle, framework, extension) and **no** forbidden paths (any `*.xcframework`, `*.dSYM`, `*.swiftmodule`, `embedded.mobileprovision`). |

CI also uploads the IPA artifact and writes a milestone summary to
the run's Summary tab via the `Job summary` step.

## 3. Manual QA checklist (Mac + signed build required to actually exercise)

Today none of the project owners has a Mac or a signing identity, so
every item below is **deferred** to whoever runs the first signed
build. The items are listed so that checklist exists when that day
comes; they are **not** blocking the current unsigned-IPA milestone.

- [ ] Launch the app on a real iPhone after the first signed build.
      Confirm it doesn't crash on launch.
- [ ] Open the **About** tab. Confirm it shows three distinct
      sections — "What this is", "Local Proxy Mode (wired)", "VPN
      Mode (scaffold / stub)", and the unsigned-IPA caveat — and
      that the "VPN Mode (scaffold / stub)" copy is honest about
      VPN Mode not being wired yet.
- [ ] Open the **Connect** tab. Leave the form empty and confirm
      **Start** is disabled. Type each field with deliberately
      invalid values (unknown provider via deep link, 4-char key,
      port `65536`) and confirm that each invalid field shows an
      inline red error message and that **Start** stays disabled.
- [ ] Import a valid `olcrtc://` URI via the system share sheet
      (`olcrtc://wbstream?datachannel@room-01#<64-hex>$Profile`).
      Confirm a new profile appears in **Profiles**, named after
      the `$<MIMO>` field, and that **Logs** does **not** contain
      the raw URI or the key bytes.
- [ ] Import an invalid `olcrtc://` URI (wrong scheme, short key,
      unknown provider). Confirm a user-facing error appears in
      **Connect** (via `lastError`) and that no profile is added.
- [ ] Import a subscription URL pointing at a plain-text file with a
      mix of valid lines, blank lines, `#`-comment lines, and a few
      malformed lines. Confirm the "X imported, Y skipped" summary
      is accurate and that **Logs** does not leak any of the raw
      input lines or key bytes.
- [ ] **Save** the current Connect-form state as a named profile
      via `Save as profile…`. Switch tabs to **Profiles** and
      confirm it appears. **Tap** the profile and confirm the form
      is repopulated. **Swipe-to-delete** and confirm it disappears
      and the saved JSON is updated.
- [ ] Run a real **Local Proxy** Start/Stop with a profile that
      points at a reachable olcRTC endpoint. Confirm the status
      card transitions Disconnected → Starting… → Running with a
      shown endpoint, that another app (e.g. a SOCKS-capable
      browser) can route traffic through `127.0.0.1:<port>`, that
      **Stop** brings it back to Disconnected, and that **Check** /
      **Ping** complete without crashing.
- [ ] Inspect the **Logs** tab after the session. Grep for any
      run of 32+ hex characters, any `keyHex=`, any `password=`,
      any literal `olcrtc://` — there must be none.
- [ ] Switch the mode picker to **VPN Mode** and confirm the
      "scaffold only" warning is visible **above** the Start
      button, and that pressing **Start** fails fast with the
      `notWiredYet` reason from `VPNManager` rather than appearing
      to succeed.

## 4. Security / privacy checklist

These are tested automatically by `LogSanitizerTests` and
`SubscriptionImporterTests`, and re-verified manually by step 3.

- [ ] **No `keyHex` in any log line.** Enforced by
      `LogSanitizer.maskHexRuns` (32+ hex chars → `<keyHex:masked>`).
      Tested by `LogSanitizerTests.test_masksRealKeyHex` and
      `…_masksKeyHexAssignment`.
- [ ] **No `password` / `pass` / `secret` value in any log line.**
      Enforced by `LogSanitizer.maskKeyValueSecrets`. Tested by
      `LogSanitizerTests.test_masksPasswordAssignment`.
- [ ] **No raw `olcrtc://` URI in any log line.** Enforced by
      `LogSanitizer.maskOlcRTCURIs`. Tested by
      `LogSanitizerTests.test_masksOlcRTCURIIncludingKey`.
- [ ] **Subscription import never logs the raw line.** The
      `SubscriptionImporter` records only `line N: <structured
      error>` — never the input bytes. Tested by
      `SubscriptionImporterTests.test_skipsInvalidLines_butKeepsValidOnes`
      (asserts the skipped-reasons array does not contain the
      sentinel line, the input room IDs, or the key bytes).
- [ ] **No secrets in CI logs.** No `gh secret`, no
      `printenv`, no `env`, no `cat *.env`, no
      `echo "$DEPLOY_KEY"` in any step of any workflow under
      `.github/workflows/`. Re-check before adding new steps.
- [ ] **Unsigned IPA is never distributed as a production
      build.** It is only published as a GitHub Actions workflow
      artifact (24 h default retention). The repo has no release
      tags and no `gh release create` step.

## 5. PacketTunnelProvider gomobile feasibility

Captures the result of the build/link probe on branch
`packet-tunnel-gomobile-probe`. This section is informational —
the unsigned-IPA pipeline (§1) does not depend on the probe, and
the probe does not produce a runtime that can be exercised on a
device. It is here so a future signing pass knows which
architectural shape to expect.

- **Probe v12 result:** `PASS-STATIC-LINKED`
  ([run 26634679085](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26634679085),
  commit `6d180e7`).
  - The `PacketTunnelProvider` extension target compiles, links,
    and embeds correctly under
    `APPLICATION_EXTENSION_API_ONLY = YES` with signing disabled.
  - The final `PacketTunnelProvider` `.appex` executable is a
    36 MB `Mach-O 64-bit executable arm64` and contains every
    gomobile-bound `Mobile*` export defined by `mobile.go`
    (`MobileStart`, `MobileStartWithTransport`,
    `MobileIsRunning`, `MobileSetDebug`, `MobileCheck`,
    `MobilePing`); `nm -u` reports no undefined `Mobile*`
    references.
  - There is **no** `OlcRTCMobile.framework` directory inside
    `.appex/Frameworks/` and **no** `.xcframework` leak into
    the `.app`.
- **Static-link model (locked in by [ADR-0013](ai/DECISIONS.md)):**
  - `gomobile bind -target=ios` emits
    `OlcRTCMobile.xcframework` as a *static* framework wrapper
    (`<slice>/OlcRTCMobile.framework/<binary>` is a
    `current ar archive`, not a Mach-O dylib).
  - The extension's framework dependency in `project.yml` is
    `embed: false / link: true / codeSign: false`.
  - The extension's `OTHER_LDFLAGS` carries
    `$(inherited) -lresolv -force_load
    $(SRCROOT)/Frameworks/OlcRTCMobile.xcframework/ios-arm64/OlcRTCMobile.framework/OlcRTCMobile`.
    `-force_load` is scoped to that one archive (no `-all_load`).
  - `APPLICATION_EXTENSION_API_ONLY = YES` stays enabled on the
    extension target.
  - Code signing and entitlements stay separate (ADR-0008); the
    `.entitlements` files remain detached from the unsigned CI
    build.
- **No runtime yet.** `PacketTunnelProvider.startTunnel` calls
  `GomobileExtensionProbe.touchNonStartingAPI()` (which only
  runs `MobileSetDebug(false)` and `MobileIsRunning()`) and
  immediately returns `StubError.notWiredYet`. The extension
  does **not** call `MobileStart*`, `MobileCheck`, or
  `MobilePing`; does **not** open sockets; does **not**
  configure `NEPacketTunnelNetworkSettings`; does **not** touch
  `NEPacketTunnelFlow`. Real lifecycle plumbing lands in
  Milestone 3.5 (`packet-tunnel-runtime-skeleton`); the actual
  VPN runtime lands in Milestone 4.
- **Future signed-device QA required.** This probe covered
  build, link, and bundle structure only — it does not say
  anything about runtime behaviour, dyld load, extension memory
  budget, or `NEPacketTunnelProvider` lifecycle on a real
  iPhone. Each of those needs to be re-verified once a signing
  identity, a provisioning profile scoped to the
  `PacketTunnelProvider` bundle ID, and the
  `com.apple.developer.networking.networkextension` entitlement
  are configured (Milestone 2 of `ROADMAP.md`).

## 6. Known limitations (today)

These are deliberate, current-state limitations — not bugs. Each
is captured in the roadmap as a planned future milestone.

- **Unsigned IPA is not installable or runnable as a normal iOS
  VPN.** Sideloading is gated on a signing identity, a
  provisioning profile scoped to the `PacketTunnelProvider` bundle
  ID, and the `com.apple.developer.networking.networkextension`
  entitlement. See ADR-0008 and Milestone 2 of the roadmap.
- **`PacketTunnelProvider` runtime is stubbed.** The extension
  target compiles, embeds, exports the right
  `NSExtensionPointIdentifier`, and (per probe v12 — see §5)
  links the gomobile static archive into its own executable
  with `Mobile*` symbols present. But its `startTunnel` still
  immediately fails with `StubError.notWiredYet`; the lifecycle
  skeleton lands in Milestone 3.5 and the real VPN runtime
  lands in Milestone 4 of the roadmap.
- **Local Proxy Mode is foreground-only.** iOS suspends a
  foreground app's process in the background; the SOCKS endpoint
  stops accepting connections when that happens. This is iOS
  behavior, not a bug. Background-safe runtime lives inside a
  `NetworkExtension` target — see Milestone 4.
- **No Apple signing workflow.** CI has no signing identity, no
  provisioning profile, no signed-build job. The unsigned IPA is
  built and uploaded; a signed pipeline is a separate workflow
  that does not exist yet. See Milestone 2.
- **No real-device QA has happened.** Every "manual QA" item
  above is deferred. Tested locally in a simulator only.
- **No App Store / TestFlight distribution path.** Distribution
  strategy is captured in Milestone 5 — until that decision is
  made, the unsigned IPA is the only artifact.

## 7. Sign-off

When all CI checks (§2) are green and §4 has been re-verified
against the changed code, this checklist is considered satisfied
for the current milestone (Local Proxy MVP, unsigned IPA).

§3 sign-off is deferred to whoever runs the first signed build
on a real iPhone.

For the next planned technical work, see
[`ROADMAP.md`](ROADMAP.md) and the **Next** section of
[`ai/TASK_LOG.md`](ai/TASK_LOG.md).
