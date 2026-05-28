# TASK_LOG.md

Running log for the iOS client track. Append to the appropriate section; do
not rewrite history. The next Claude session reads this to pick up cold, so
write entries that make sense without the surrounding chat.

Date format: `YYYY-MM-DD`. Each entry should answer **what** changed and
**why**, not narrate process.

---

### 2026-05-28 — Harden profile import and Local Proxy MVP UX

- Goal: make the Connect / Profiles / Logs / About surface actually
  usable for configuring Local Proxy Mode against a real olcRTC
  endpoint. Audit found: validation was a one-liner stub, Start was
  enabled with empty/garbage fields, the Profiles tab was read-only,
  there was no subscription importer at all, the URI parser did not
  percent-decode and did not enforce the 64-char hex key requirement,
  and the About copy still described the app as a generic "VPN
  client" without making the Local Proxy = wired / VPN Mode = stub
  distinction obvious to a first-time user. UI-only step — no Go
  core change, no gomobile wired into `PacketTunnelProvider`, no
  signing, no new CI workflow.
- Shared layer changes (compiled into both app and extension; only
  app uses them today, but extension keeps building under
  `APPLICATION_EXTENSION_API_ONLY = YES` because all new code is
  pure Foundation):
  - **New `ProfileValidator`** (`Sources/Shared/Services/`). Pure
    validator, no I/O. Enforces the rules from the task brief:
    provider ∈ `{jitsi, telemost, wbstream}`, transport ∈
    `{datachannel, vp8channel}`, room/clientID non-empty after trim,
    `keyHex` exactly 64 hex chars (lower or upper case), SOCKS host
    non-empty, SOCKS port parseable into `1...65535`. DNS server
    stays an optional free-form string until the Go core surfaces a
    canonical format. Returns `[Issue]` (field + message) instead of
    throwing on the first miss so the UI shows every problem at
    once.
  - **New `SubscriptionImporter`** (`Sources/Shared/Services/`).
    Fetches an `http://` / `https://` URL with an ephemeral
    `URLSession` (15 s request timeout, no cookies, no cache),
    decodes the body as UTF-8 with a Latin-1 fallback, splits on
    newlines, treats `#`-prefixed lines as comments, and runs each
    remaining line through `OlcRTCURIParser`. Invalid lines are
    skipped (not fatal); the returned `Outcome` carries the imported
    profile array, a skipped count, and per-line skipped reasons.
    Skipped reasons never include the raw line or the key — only the
    line number plus the structured `ParseError.description` (length
    of the bad key when relevant; never the bytes).
  - **`OlcRTCURIParser` hardened**: percent-decodes `roomID` and
    `mimo` (so jitsi-style room URLs with `%20` and MIMO comments
    with `%2F` round-trip cleanly); validates the encryption key as
    exactly 64 hex characters at parse time and normalizes it to
    lowercase; new `ParseError.invalidKeyHex(String)` case that
    surfaces only the length, never the value;
    `Parsed.toProfile(name:)` uses the trimmed MIMO as the profile's
    display name when present, falling back to the caller-supplied
    name otherwise.
  - **`ProfileStore` extended** with `isDuplicate(_:_:)` and
    `mergingWithoutDuplicates(existing:adding:)` helpers. Duplicate
    test is the (provider, transport, room, key, clientID) tuple —
    `name`, SOCKS port, DNS, etc. are local knobs and don't count.
- App-layer changes:
  - **`AppState` rewrite**: default mode is now `.localProxy` (it's
    the only mode wired to a real runtime); `currentProfile()`
    trims whitespace and lowercases the key before forwarding; new
    `validationIssues` array with `refreshValidation()` hooked onto
    every field's `onChange`; new `canStart` /
    `validationMessage(for:)` helpers consumed by the views; `start()`
    refuses to start when invalid (sets `status = .failed(reason:)`
    + `lastError`); `check()` is now a real validation report instead
    of a stub; new `saveCurrentProfile(name:)`, `selectProfile(_:)`,
    `deleteProfile(_:)`, `deleteProfiles(at:)`, `importURI(_:)`,
    `importSubscription(urlString:)`; `handleIncomingURL` reuses
    `importURI` so deep links go through the same dedup/sanitize
    path; logs continue to flow through `LogSanitizer`.
  - **`ConnectView`** shows inline red error rows under each field
    when the validator flags it, disables `Start` when validation
    fails, and gains a `Save as profile…` button + sheet for naming
    the current form-state and persisting it.
  - **`ProfilesView`** is no longer read-only: tap to load a profile
    into the Connect form, swipe-to-delete, toolbar `+` menu with
    `Import olcrtc:// URI` and `Import subscription URL` sheets.
    Empty state offers the same two import buttons.
  - **`AboutView`** copy split into "Local Proxy Mode (wired)" vs
    "VPN Mode (scaffold / stub)" sections so the difference is
    obvious without scrolling to the bottom; unsigned-IPA disclaimer
    now references the artifact by its actual CI name.
  - **`LogsView` placeholder lines** updated to reflect today's
    reality (Local Proxy wired / VPN stub) instead of the older
    "gomobile bridge not linked yet" wording.
- New / extended tests (run under the existing
  `Run tests (iphonesimulator)` step in
  `iOS App + Gomobile Build`):
  - `OlcRTCURIParserTests` — new cases for the canonical
    jitsi/datachannel and wbstream/vp8channel URIs, percent-decoded
    room + MIMO, short key rejection, non-hex key rejection,
    unsupported provider (`zoom`) and unsupported transport
    (`webrtc`), a jitsi URL room containing `?id=42` (must still
    split on the last `#`), uppercase key normalization to
    lowercase.
  - New `ProfileValidatorTests` — fully-valid input, unknown
    provider, unknown transport, empty room + empty clientID, short
    key, non-hex key, uppercase-accepted key, bad ports (`""`,
    `"0"`, `"65536"`, `"abc"`, `"-1"`, `"8.8"`), boundary ports
    (`"1"`, `"65535"`, `"8080"`).
  - New `SubscriptionImporterTests` — multiple valid lines, comment
    + blank-line filtering, mixed valid + invalid lines (valid ones
    survive), empty-body case. Each test that exercises a "skipped"
    path also asserts the skipped reason does **not** contain the
    raw key or the raw `olcrtc://` URI.
- Documentation:
  - `ios/OlcRTCClient/README.md` gained a **UI usage (Local Proxy
    MVP)** section walking the Connect / Profiles / Logs / About
    tabs, the validation rules, and the URI / subscription import
    flows. Repeats the privacy guarantees (no key, no full URI, no
    raw subscription line written to logs).
- **Not done in this step**, intentionally: any Go-core change; any
  wiring of `OlcRTCMobile.xcframework` into the
  `PacketTunnelProvider` extension; any real
  `NETunnelProviderManager` install; any signing; any new feature
  beyond what the task brief listed; any change to the IPA
  packaging or workflow YAML (the new tests run inside the
  pre-existing `Run tests` step, no workflow edit needed).

---

### 2026-05-28 — Validate unsigned IPA artifact structure

- Goal: lock in the IPA layout produced by
  `iOS App + Gomobile Build` so a future change that silently
  breaks packaging (Xcode embedding the multi-slice `.xcframework`
  instead of the iphoneos slice, dropping the
  `PacketTunnelProvider.appex` plug-in, accidentally including a
  `.dSYM` / `.swiftmodule` / `embedded.mobileprovision`) fails the
  workflow loudly instead of uploading a subtly-broken artifact.
  Inspection only — no code-behavior change, no Go-core change, no
  PacketTunnelProvider wiring, no signing.
- Manual inspection of the artifact from the latest green run
  (https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26595550400)
  via `gh run download` of `OlcRTCClient-unsigned-ipa`. Findings:
  - The IPA is a plain zip with a single top-level `Payload/`
    directory, as expected.
  - Verified `find Payload -maxdepth 5 -print | sort` output:
    ```
    Payload
    Payload/OlcRTCClient.app
    Payload/OlcRTCClient.app/Frameworks
    Payload/OlcRTCClient.app/Frameworks/OlcRTCMobile.framework
    Payload/OlcRTCClient.app/Frameworks/OlcRTCMobile.framework/Info.plist
    Payload/OlcRTCClient.app/Frameworks/OlcRTCMobile.framework/OlcRTCMobile
    Payload/OlcRTCClient.app/Info.plist
    Payload/OlcRTCClient.app/OlcRTCClient
    Payload/OlcRTCClient.app/PkgInfo
    Payload/OlcRTCClient.app/PlugIns
    Payload/OlcRTCClient.app/PlugIns/PacketTunnelProvider.appex
    Payload/OlcRTCClient.app/PlugIns/PacketTunnelProvider.appex/Info.plist
    Payload/OlcRTCClient.app/PlugIns/PacketTunnelProvider.appex/PacketTunnelProvider
    ```
  - App bundle metadata (from binary `Info.plist`):
    `CFBundleIdentifier = org.openlibrecommunity.olcrtc.client`,
    `CFBundleExecutable = OlcRTCClient`,
    `CFBundleShortVersionString = 0.1.0`,
    `CFBundleVersion = 1`,
    `MinimumOSVersion = 16.0`,
    `DTSDKName = iphoneos18.5`,
    `CFBundleSupportedPlatforms = [iPhoneOS]`,
    URL scheme registered: `olcrtc`.
  - Extension bundle metadata
    (`PlugIns/PacketTunnelProvider.appex/Info.plist`):
    `CFBundleIdentifier = org.openlibrecommunity.olcrtc.client.PacketTunnelProvider`,
    `CFBundleExecutable = PacketTunnelProvider`,
    `NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel`,
    `NSExtensionPrincipalClass = PacketTunnelProvider.PacketTunnelProvider`.
  - Embedded framework Info.plist
    (`Frameworks/OlcRTCMobile.framework/Info.plist`):
    `CFBundleExecutable = OlcRTCMobile`,
    `CFBundleIdentifier = OlcRTCMobile`,
    `CFBundlePackageType = FMWK`,
    `MinimumOSVersion = 100.0` (gomobile default — harmless, since
    the host app pins `MinimumOSVersion = 16.0` and the iOS loader
    honors the host's value; this is recorded here so a future
    reviewer doesn't panic at `100.0`).
  - Mach-O architectures (`file`):
    - `OlcRTCClient` — Mach-O arm64 executable (38,176,168 B).
    - `Frameworks/OlcRTCMobile.framework/OlcRTCMobile` — Mach-O
      universal w/ 1 arch arm64 dynamically linked shared library
      (33,128 B).
    - `PlugIns/PacketTunnelProvider.appex/PacketTunnelProvider` —
      Mach-O arm64 executable (254,104 B).
    No simulator slice leaked into the device IPA.
  - **No** `_CodeSignature/`, `embedded.mobileprovision`,
    `*.xcframework`, `*.dSYM`, or `*.swiftmodule` directories
    anywhere in `Payload/` — confirmed via `find`. Unsigned and
    free of dev-only artifacts, as expected.
  - **Size note**: the main app binary is ≈38 MB because the Go
    runtime is statically linked into the host's
    `OlcRTCClient` Mach-O (gomobile's c-archive flow leaves the
    framework binary itself tiny at ≈33 KB and lets the host link
    pull the bulk in). This is expected, not a bug — but worth
    knowing the next time someone asks "why is the app binary so
    big and the framework so small?".
- Changes in `.github/workflows/ios-app-gomobile.yml` (CI now does
  the same inspection automatically, every run):
  - New `Inspect and validate unsigned IPA structure` step (runs
    right after `Upload unsigned IPA artifact`). Steps:
    1. `unzip` the freshly-built `build/ipa/OlcRTCClient-unsigned.ipa`
       into `build/ipa-inspect/`.
    2. Print `find Payload -maxdepth 5 -print | sort`.
    3. Assert every required path exists (`OlcRTCClient.app`,
       `Info.plist`, the app binary, `Frameworks/OlcRTCMobile.framework`
       + its `Info.plist` + its binary, `PlugIns/PacketTunnelProvider.appex`
       + its `Info.plist` + its binary). Missing path → step fails
       with the offending path in stderr.
    4. Assert no forbidden paths exist anywhere in the bundle:
       any `*.xcframework` directory (would mean a packaging
       regression where Xcode kept the multi-slice wrapper),
       any `*.dSYM`, any `*.swiftmodule`, any
       `embedded.mobileprovision`. Each forbidden hit → step fails
       with the matched path in stderr.
    5. Print app / extension / framework `Info.plist` excerpts via
       `plutil -p` filtered to the keys we care about
       (`CFBundleIdentifier`, `CFBundleExecutable`,
       `CFBundleShortVersionString`, `CFBundleVersion`,
       `MinimumOSVersion`, `DTSDKName`, `DTPlatformVersion`,
       `CFBundleSupportedPlatforms`, `NSExtensionPointIdentifier`,
       `NSExtensionPrincipalClass`, `CFBundlePackageType`).
    6. Print `ls -la` of `Frameworks/` and `PlugIns/`, the byte
       sizes of all three Mach-O binaries (via `stat -f '%z'`,
       which is the BSD form available on `macos-latest`), and
       `file` output for those three binaries so the runner image's
       Mach-O introspection ends up in the log alongside everything
       else.
- Updated `ios/OlcRTCClient/README.md` with a new
  **"IPA structure (validated by CI)"** subsection under the
  existing **"Unsigned IPA artifact (CI only)"** section: shows the
  expected bundle tree, the explicit forbidden-path list, and the
  size/Go-runtime note from the inspection.
- Added `ipa-inspect-tmp/` to `.gitignore` so manual artifact
  downloads done on a dev machine never accidentally get committed.
  (CI uses `build/ipa-inspect/` which is already ignored by the
  existing `build/` rule.)
- **Not done in this step**, intentionally: any code-behavior
  change; any Go-core change; any wiring of
  `OlcRTCMobile.xcframework` into `PacketTunnelProvider`; any
  signing; any new feature.

---

### 2026-05-28 — Milestone: unsigned IPA artifact packaging green

- Milestone state: `iOS App + Gomobile Build` is green end-to-end and
  now produces the first unsigned IPA artifact from CI. This closes
  step 7 ("Unsigned `.ipa` packaging step") in the **Next** plan
  below — the section is left intact for historical context but the
  IPA item is **done**.
- Reference run (the first green one with the IPA artifact attached):
  https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26595108591
- Artifact: `OlcRTCClient-unsigned-ipa` (≈11 MB, expires per the
  GitHub Actions default — re-run the workflow to refresh it).
- Snapshot of what is and is not wired at this milestone:
  - **Wired**: `OlcRTCMobile.xcframework` built from the upstream
    submodule, linked into the main app target, Local Proxy Mode
    talking to the real gomobile API (`Start` / `Stop` / `Check` /
    `Ping` / `IsRunning` / `WaitReady` / `SetLogWriter`), simulator
    Debug build green, simulator unit tests green, Release iphoneos
    generic unsigned build green, validation + Payload zip + IPA
    artifact upload green.
  - **Not wired**: `PacketTunnelProvider` runtime (still a
    `notWiredYet` stub — the extension target compiles and embeds
    but does not link `OlcRTCMobile.xcframework`), real signing,
    Apple Developer account, provisioning profile,
    `com.apple.developer.networking.networkextension` entitlement,
    re-attached `.entitlements` in `project.yml`.
- Documentation cleanup landing with this milestone:
  - Root `README.md` rewritten with an up-to-date **Status (current)**
    block listing the standalone-repo identity, the
    `third_party/olcrtc` submodule, the green workflow name, the
    artifact name, what Local Proxy Mode does today, and the
    unsigned-IPA caveats.
  - `.github/workflows/ios-app-gomobile.yml` gained a final
    `Job summary` step (runs with `if: always()`) that writes the
    build result, commit SHA, run URL, artifact name, the
    "CI / later-signing only" caveat, and the "PacketTunnelProvider
    runtime is still stubbed" caveat to `$GITHUB_STEP_SUMMARY` so
    the milestone state shows on the run's Summary tab without
    requiring anyone to scroll the log.
- Next recommended steps (small, reviewable, in order):
  1. **Download and inspect the artifact.** Pull
     `OlcRTCClient-unsigned-ipa` from a green run, unzip it, confirm
     the `Payload/OlcRTCClient.app` layout, confirm
     `OlcRTCMobile.framework` is embedded under the app bundle,
     confirm no `_CodeSignature/` exists, sanity-check `Info.plist`
     keys. This is read-only verification — no code changes
     expected.
  2. **Improve UI/UX and profile import.** Tighten the SwiftUI
     surface for the Connect / Profiles / Logs / About tabs; finish
     `olcrtc://` URI import polish; start on subscription import per
     `docs/sub.md` (HTTPS fetch + parse + merge). Local-only,
     app-target-only work — no extension wiring yet.
  3. **Later, evaluate gomobile inside `PacketTunnelProvider`.**
     Verify `OlcRTCMobile.xcframework` links cleanly under
     `APPLICATION_EXTENSION_API_ONLY = YES`; if it does, wire
     `NEPacketTunnelNetworkSettings` + the Go runtime + the
     `PacketTunnelConfig` handoff in the extension. Real-device
     runtime is still gated on signing — that is fine for the
     wiring step; the test is "extension links and starts a Go
     runtime in a process, not that it tunnels packets on a stock
     iPhone".
- **Not done in this step**, intentionally: any code-behavior change,
  any Go-core edit, any wiring of gomobile into
  `PacketTunnelProvider`, any signing, any new feature. This is a
  documentation/status cleanup only.

---

### 2026-05-28 — Package unsigned IPA artifact in CI

- Goal: after the green Release `iphoneos` generic unsigned build in
  `iOS App + Gomobile Build`, package the built `.app` into an unsigned
  `.ipa` and upload it as a workflow artifact, so a later signed-build
  pipeline has a stable input to re-sign. No new features, no Go-core
  changes, no wiring of gomobile into `PacketTunnelProvider`, no real
  signing, no Apple Developer requirements added.
- Changes in `.github/workflows/ios-app-gomobile.yml`:
  - Added `-derivedDataPath build/DerivedData` to every `xcodebuild`
    invocation in the workflow (Debug simulator build, simulator
    tests, Release iphoneos generic build) so the product path is
    deterministic and not buried under a randomized
    `~/Library/Developer/Xcode/DerivedData/<hash>` directory.
  - New `Locate built .app` step prints
    `find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 2 -type d -name "*.app" -print`
    and an `ls -la` of the products dir, so any future drift in
    Xcode's output layout is obvious from the workflow log.
  - New `Validate .app bundle before packaging` step fails the run
    early if any of the following are missing:
    `build/DerivedData/Build/Products/Release-iphoneos/OlcRTCClient.app`
    (directory),
    `.../OlcRTCClient.app/Info.plist` (file),
    `.../OlcRTCClient.app/OlcRTCClient` (the Mach-O binary).
  - New `Package unsigned IPA` step creates `build/ipa/Payload/`,
    copies the bundle to `build/ipa/Payload/OlcRTCClient.app`, then
    zips from inside `build/ipa` so the archive's top-level entry is
    `Payload/OlcRTCClient.app/...` — the layout `iOS` and `ideviceinstaller`
    expect from an IPA. Output:
    `build/ipa/OlcRTCClient-unsigned.ipa`.
  - New `Upload unsigned IPA artifact` step uploads the archive as the
    `OlcRTCClient-unsigned-ipa` workflow artifact with
    `if-no-files-found: error`, so a silent packaging regression is
    impossible.
- Updated `ios/OlcRTCClient/README.md` with a new
  **"Unsigned IPA artifact (CI only)"** section. Records:
  - the artifact is generated by CI from the Release iphoneos build;
  - it is **for CI / later signing only**;
  - it is **not** expected to install or run VPN on ordinary iPhones
    without an Apple Developer account, a provisioning profile scoped
    to the `PacketTunnelProvider` bundle ID, the
    `com.apple.developer.networking.networkextension` entitlement, and
    a signed build with those attached.
  - Removed the now-stale "No unsigned `.ipa` packaging yet" bullet
    from the **What is not here today** section.
- **Not done in this step**, intentionally: any Go-core change; any
  wiring of `OlcRTCMobile.xcframework` into the
  `PacketTunnelProvider` extension; any real signing identity /
  provisioning profile / `NetworkExtension` entitlement; any new
  app features; reattaching `.entitlements` files in `project.yml`;
  modifying the isolated `Gomobile iOS Bind` workflow (it still only
  produces and uploads the xcframework + inspection report and does
  not package an IPA — only `iOS App + Gomobile Build` does).

---

### 2026-05-28 — Link `libresolv` for OlcRTCMobile app target

- Goal: get `iOS App + Gomobile Build` past the Debug iphonesimulator
  link step. After the Swift compile errors were fixed
  ([run 26592753259](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26592753259)),
  Swift compiled clean but `ld` failed with:

  ```
  Undefined symbols for architecture x86_64:
    "_res_9_nclose", referenced from: _runtime.text in OlcRTCMobile(go.o)
    "_res_9_ninit",  referenced from: _runtime.text in OlcRTCMobile(go.o)
    "_res_9_nsearch", referenced from: _runtime.text in OlcRTCMobile(go.o)
  ld: symbol(s) not found for architecture x86_64
  ```

  These are BSD resolver symbols. The Go runtime/stdlib (inside the
  gomobile-built `OlcRTCMobile.xcframework`) references them, but iOS
  does not link `libresolv` by default. The host target has to.
- Fix: `ios/OlcRTCClient/project.yml` now sets
  `OTHER_LDFLAGS: $(inherited) -lresolv` on the **main app target
  only**. The `PacketTunnelProvider` extension is not yet linked to
  `OlcRTCMobile.xcframework`, so it does not need the flag today —
  when the extension starts linking the framework (a later step), the
  same flag will be added there.
- Did **not** restrict simulator architectures (`EXCLUDED_ARCHS`,
  `VALID_ARCHS`, etc.) to mask the symptom on x86_64 — both simulator
  slices must keep linking so the same fix works for arm64-only
  device builds.
- Updated `docs/ai/GOMOBILE_BINDINGS.md` section 4 with the
  `libresolv` requirement and the discovery context.
- **Not done in this step**, intentionally: linking
  `OlcRTCMobile.xcframework` into `PacketTunnelProvider`, IPA
  packaging, Go-core changes, signing.

---

### 2026-05-28 — Fix Swift gomobile service integration compile errors

- Goal: get `iOS App + Gomobile Build` past the `Build app (Debug,
  iphonesimulator)` step. The previous `Wire Local Proxy Mode to real
  gomobile API` commit compiled against assumed gomobile signatures
  that turned out to be wrong once the framework actually built.
- Robust CI destination (commit `a9d18a9`) unblocked the simulator
  build runner-side; the next run exposed a wall of Swift compile
  errors against the real generated headers
  ([run 26591390505](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26591390505)).
- Concrete fixes in this step:
  - **`OlcRTCProfile`** now carries three liveness fields with safe
    defaults that match the Go core (`livenessIntervalMillis = 30000`,
    `livenessTimeoutMillis = 10000`, `livenessFailures = 3`), plus a
    custom `init(from:)` so previously-persisted profile JSON (which
    has none of these keys) still decodes.
  - **`LocalProxyManager`** unwraps optional `vp8FPS` / `vp8BatchSize`
    with safe defaults (`30` and `1`) at the call sites that forward
    them to `RealOlcRTCService`. The Go core expects plain `int`, not
    `Int?`.
  - **`RealOlcRTCService`** stops assuming that gomobile `BOOL fn(...,
    NSError**)` shapes auto-import as Swift `throws`. They do not —
    the Swift importer leaves them as raw Obj-C signatures. Every call
    site now allocates `var err: NSError?` (and, for `Check`/`Ping`,
    `var ret: Int64 = 0`), passes them by pointer, inspects the `Bool`
    return, and throws `err ?? RealOlcRTCServiceError.<reason>` on
    `false`. Added a local `RealOlcRTCServiceError` enum so a `false`
    return without an `NSError` (defensive) still produces a useful
    `LocalizedError`.
  - `SwiftLogWriter` now uses an instance `LogSanitizer()` (the type
    is a `struct` with an instance `sanitize(_:)` method; the previous
    static-method call site would not compile).
  - `AppState.ping()` no longer references `mock` unconditionally —
    the `mock` property is gated behind `#if !canImport(OlcRTCMobile)`,
    so the function body is too.
- Updated `docs/ai/GOMOBILE_BINDINGS.md`:
  - Section 2 (symbol mapping) replaced "Swift throws" entries with
    the real `BOOL` + `NSError**` calling convention discovered at
    compile time.
  - Section 3 (log writer) documents the `MobileLogWriter` /
    `MobileLogWriterProtocol` rename caused by the same-named Obj-C
    class + protocol.
  - Section 4 (compile-validated unknowns) records the exact Swift
    call shapes that finally compiled for `Start`, `WaitReady`,
    `Check`, `Ping`.
- **Not done in this step**, intentionally: any new UI for liveness
  configuration, any change to `MockOlcRTCService` (still used by
  scaffold-only builds), wiring gomobile into `PacketTunnelProvider`,
  IPA packaging, Go-core changes.

---

### 2026-05-28 — Make iOS simulator destination robust in CI

- Goal: stop both iOS CI workflows from depending on a specific
  simulator device name (`iPhone 16`) that may or may not be
  installed on the GitHub Actions macOS runner image.
- Background: the run after the `MobileLogWriter` /
  `MobileLogWriterProtocol` fix failed at `Build app (Debug,
  iphonesimulator)` **before** any Swift was compiled, with
  `xcodebuild: error: Unable to find a device matching the provided
  destination specifier: { platform:iOS Simulator, OS:latest, name:iPhone 16 }`.
  An earlier run on a different runner instance found `iPhone 16`
  fine, so this is a runner-image flake, not a project bug.
- Changes in `.github/workflows/ios-app-gomobile.yml` and
  `.github/workflows/ios-scaffold.yml` (same edits applied to both):
  - Added a `Diagnose simulator availability` step that prints
    `xcrun simctl list devices available` and `xcodebuild -showsdks`
    so future runner flakes are obvious from the log.
  - Added a `Pick iOS Simulator destination` step that parses
    `simctl list devices available -j`, picks the first available
    `iPhone*` simulator across all installed iOS runtimes, and writes
    `IOS_SIMULATOR_DESTINATION=platform=iOS Simulator,id=<UDID>` to
    `$GITHUB_ENV`. If no concrete iPhone simulator is available it
    falls back to `IOS_SIMULATOR_DESTINATION=generic/platform=iOS
    Simulator`.
  - `xcodebuild build` for the simulator uses the static
    `generic/platform=iOS Simulator` destination (build doesn't need a
    bootable device).
  - `xcodebuild test` uses `${IOS_SIMULATOR_DESTINATION}` (tests
    require a concrete bootable simulator).
- The `Release iphoneos generic` build step is unchanged — it already
  uses `generic/platform=iOS` and never had this issue.
- **Not done in this step**, intentionally: IPA packaging, signing,
  wiring gomobile into `PacketTunnelProvider`, any Swift-code change.

---

### 2026-05-28 — Local Proxy Mode wired to real gomobile API

- Goal: replace `MockOlcRTCService` with calls to the real
  `OlcRTCMobile.xcframework` in the main app target for Local Proxy
  Mode. PacketTunnelProvider is still stubbed and does NOT link the
  framework yet (that happens in a later step once
  `APPLICATION_EXTENSION_API_ONLY` compatibility is validated).
- Updated `docs/ai/GOMOBILE_BINDINGS.md` with the discovered symbol
  mapping from workflow run
  [26588577428](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26588577428):
  - Framework name: `OlcRTCMobile.framework`
  - Module name (Swift `import`): `OlcRTCMobile`
  - All Go package-level functions surface with a `Mobile` prefix:
    `MobileSetProviders`, `MobileSetTransport`, `MobileStart`,
    `MobileStartWithTransport`, `MobileCheck`, `MobilePing`,
    `MobileStop`, `MobileIsRunning`, `MobileWaitReady`,
    `MobileSetLogWriter`, etc.
  - Go `error` → Obj-C `BOOL` return + `NSError**` out-param → Swift
    throwing function.
  - Go `(int64, error)` → Obj-C `BOOL` + `int64_t* ret0_` +
    `NSError**` → Swift `throws -> Int64`.
  - `MobileLogWriter` protocol exists; Swift implements via a class
    conforming to it.
- Added `ios/OlcRTCClient/Sources/App/Services/RealOlcRTCService.swift`:
  - Only compiled when `#if canImport(OlcRTCMobile)`.
  - Calls `MobileSetProviders`, `MobileSetTransport`, `MobileSetDNS`,
    `MobileSetSocksListenHost`, `MobileSetVP8Options`,
    `MobileSetLivenessOptions`, `MobileSetDebug` before start.
  - Calls `MobileStartWithTransport` for start,
    `MobileStop` for stop, `MobileIsRunning` for status,
    `MobileCheck` for Check, `MobilePing` for Ping.
  - Implements `MobileLogWriter` in Swift (`SwiftLogWriter`) and
    routes logs through `LogSanitizer` before forwarding to the app
    log sink.
- Updated `ios/OlcRTCClient/Sources/App/Services/LocalProxyManager.swift`:
  - When `canImport(OlcRTCMobile)`: uses `RealOlcRTCService`.
  - Otherwise: falls back to `MockOlcRTCService` for scaffold-only
    builds.
- Updated `ios/OlcRTCClient/Sources/App/AppState.swift`:
  - When `canImport(OlcRTCMobile)`: creates `LocalProxyManager` with
    a log sink that appends to the in-app log buffer.
  - Otherwise: creates `LocalProxyManager` with `MockOlcRTCService`.
- Updated `ios/OlcRTCClient/project.yml`:
  - Added `FRAMEWORK_SEARCH_PATHS: $(inherited) $(PROJECT_DIR)/Frameworks`
    to the main app target.
  - Added `OlcRTCMobile.xcframework` as a framework dependency for
    the main app target (`embed: true, codeSign: false`).
  - The framework is **not** linked into `PacketTunnelProvider` yet.
  - The framework is gitignored and must not be committed.
- Added `.github/workflows/ios-app-gomobile.yml` (`name: iOS App + Gomobile Build`):
  - Checkout with submodules recursive.
  - Setup Go from `third_party/olcrtc/go.mod`.
  - Install XcodeGen.
  - Run `scripts/build-gomobile-ios.sh`.
  - Generate Xcode project (`xcodegen generate`).
  - Build Debug simulator unsigned.
  - Run tests.
  - Build Release iphoneos generic unsigned.
  - Does **not** package IPA yet.
- Kept the existing `iOS Scaffold Build` and `Gomobile iOS Bind`
  workflows as isolated checks.
- **Not done in this step**, intentionally: linking the framework into
  `PacketTunnelProvider`, VPN Mode runtime, IPA packaging, Go-core
  changes, signing.

---

- Goal: capture the **real** generated Obj-C / Swift surface of
  `OlcRTCMobile.xcframework` so the next step (wiring `LocalProxyManager`
  to the real Go API) does not guess symbol names. `gomobile bind`
  applies its own name-mangling (package prefix, exported-method
  casing, error/multi-return flattening); the only reliable source of
  truth is the generated headers/module maps themselves.
- `scripts/build-gomobile-ios.sh` now, after a successful
  `gomobile bind`, also writes a mechanical inspection bundle to
  `build/reports/gomobile/`:
  - `files.txt` — `find -maxdepth 5 -type f` of the xcframework.
  - `headers.txt` — first 240 lines of every `*.h` inside the
    xcframework.
  - `modulemaps.txt` — full content of every `module.modulemap`.
  - `swiftinterfaces.txt` — first 240 lines of every
    `*.swiftinterface` (empty when gomobile only emits Obj-C, which
    is the current default).
  - `summary.md` — a parsed view of the first framework slice
    (framework name, primary header, module map path, grep'd
    `@interface` / `FOUNDATION_EXPORT` / `extern` declarations).
  All five reports are also echoed to stdout, so CI logs are
  self-contained for quick triage.
- `.github/workflows/gomobile-ios-bind.yml` now uploads **two**
  artifacts on a successful run:
  - `OlcRTCMobile-xcframework` — the framework (unchanged).
  - `gomobile-inspection-report` — the contents of
    `build/reports/gomobile/`.
- Added `.gitignore` entry for `build/` so the reports stay
  uncommitted; they live in CI artifacts, not in the repo.
- Added `docs/ai/GOMOBILE_BINDINGS.md` — the curated reference for
  the iOS bindings. The first commit only contains the **skeleton**
  (Go-side surface + sections to fill in + refresh procedure); the
  follow-up commit will paste in the verbatim symbol names from the
  `gomobile-inspection-report` artifact of the green CI run, so we
  record real names rather than guesses.
- **Not done in this step**, intentionally: wiring
  `OlcRTCMobile.xcframework` into `project.yml`, calling Go from
  `LocalProxyManager` / the extension, IPA packaging, any Go-core
  changes, any Swift-side compile validation of the symbol mapping
  (that happens in the next step once the symbol names are
  recorded).

---

- First run of `Gomobile iOS Bind` failed at the
  `Build OlcRTCMobile.xcframework` step. Root cause from the workflow
  log: `gomobile bind` was invoked from the standalone iOS repo root,
  which has **no `go.mod`**, so it could not find
  `golang.org/x/mobile` in any module dependency graph and bailed
  with:

  ```
  gomobile bind requires golang.org/x/mobile in the current module,
  but it is not in the module dependency graph.
  Add it with:
      go get -tool golang.org/x/mobile/cmd/gobind
  gomobile: missing golang.org/x/mobile dependency
  ```

  The remediation the error suggests (`go get -tool ...`) would
  mutate `third_party/olcrtc/go.mod`, which is **upstream Go core** —
  forbidden by the current task brief and by `CLAUDE.md`.

- Attempted fix (this commit): run `gomobile bind` from **inside**
  the upstream Go module instead of from the iOS repo root.
  `third_party/olcrtc/go.mod` already exists and already owns the
  `./mobile` package, so it is the natural home for the bind
  dependency graph. `scripts/build-gomobile-ios.sh` now:
  - resolves the repo root (unchanged),
  - verifies both `third_party/olcrtc/go.mod` and
    `third_party/olcrtc/mobile` exist,
  - prepends `$(go env GOPATH)/bin` to `PATH`,
  - installs `golang.org/x/mobile/cmd/gomobile@latest` and
    `golang.org/x/mobile/cmd/gobind@latest` if missing
    (`go install` resolves via the build cache and does NOT touch the
    upstream module),
  - runs `gomobile init`,
  - `cd third_party/olcrtc`,
  - prints diagnostics from inside the upstream module: `pwd`,
    `go env GOMOD`, `go list -m golang.org/x/mobile` (best-effort —
    will fail if not in graph, but we want to see that), and
    `go test -count=1 ./mobile`,
  - runs:
    ```
    gomobile bind -v \
      -target=ios \
      -o ../../ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework \
      ./mobile
    ```
  - returns to repo root for the output inspection.
  Explicit non-actions in the script (commented at the top):
  no `go get`, no edits to `third_party/olcrtc/go.mod`, no edits to
  `third_party/olcrtc/go.sum`, no wrapper module, no `go.work`.
- The workflow file `.github/workflows/gomobile-ios-bind.yml` is
  unchanged in this commit. It already checks out submodules
  recursively, sets up Go via `third_party/olcrtc/go.mod`, runs
  `go test -count=1 ./mobile` inside `third_party/olcrtc`, then
  delegates to the script — that wiring is still correct now that
  the script itself moves into the upstream module before bind.

#### Fallbacks if this attempt also fails

If `gomobile bind` from inside `third_party/olcrtc` still rejects
the build (most likely cause: `golang.org/x/mobile` not in the
upstream module's dependency graph and we are not allowed to add it
there), the next escalation is — in order of increasing invasiveness,
each requiring its own ADR / brief:

1. **Local wrapper module** in this repo (e.g. a tiny `go.mod` under
   `scripts/gomobile-shim/` that imports
   `github.com/openlibrecommunity/olcrtc/mobile` via a `replace`
   directive pointing at `../../third_party/olcrtc` and declares
   `golang.org/x/mobile` as a tool dependency). `gomobile bind` runs
   inside the shim, but `./mobile` source still comes from upstream.
2. **`go.work` at this repo's root** listing
   `third_party/olcrtc` and a tiny local module that holds the
   gomobile tool dependency. Same idea as (1), expressed via
   workspaces.
3. **Last resort**: open an upstream PR adding `golang.org/x/mobile`
   to `third_party/olcrtc/go.mod` (this is a Go-core change — not
   allowed from this repo per ADR-0011).

Do not pre-implement these in this step.

---

- Goal of this step: verify that the standalone iOS repo can produce
  `OlcRTCMobile.xcframework` from the upstream Go core
  (`third_party/olcrtc/mobile`) on a macOS CI runner, **without**
  integrating the framework into the Swift app yet, without changing
  Swift UI, without changing the Go core, and without IPA packaging.
- Added `scripts/build-gomobile-ios.sh` (executable, LF-only). The
  script:
  - resolves the repo root and `cd`s there regardless of how it is
    invoked,
  - verifies `third_party/olcrtc/mobile` exists,
  - prints `go version`, `xcodebuild -version`, and any pre-existing
    `gomobile version`,
  - installs `golang.org/x/mobile/cmd/gomobile@latest` and
    `golang.org/x/mobile/cmd/gobind@latest` if they are missing,
  - prepends `$(go env GOPATH)/bin` to `PATH`,
  - runs `gomobile init`,
  - runs
    `gomobile bind -v -target=ios -o ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework ./third_party/olcrtc/mobile`,
  - prints the directory tree of the produced `.xcframework`, any
    generated `*.h`, and any generated `*.swiftinterface` files,
  - prints the gitignored status reminder.
- Added `.github/workflows/gomobile-ios-bind.yml` (`name: Gomobile iOS Bind`).
  Triggers: `workflow_dispatch` and `push` filtered to
  `scripts/build-gomobile-ios.sh`,
  `.github/workflows/gomobile-ios-bind.yml`, `.gitmodules`,
  `third_party/olcrtc`, and `docs/ai/**`. Runner: `macos-latest`.
  Steps, in order:
  1. `actions/checkout@v4` with `submodules: recursive`.
  2. `git submodule status --recursive`.
  3. `actions/setup-go@v5` with
     `go-version-file: third_party/olcrtc/go.mod`. If that Go version
     is unavailable on the runner, the step fails loudly — we do not
     silently downgrade Go and we do not edit upstream `go.mod` in
     this repo (ADR-0011).
  4. `go version`.
  5. `go test -count=1 ./mobile` inside `third_party/olcrtc`.
  6. `scripts/build-gomobile-ios.sh`.
  7. `actions/upload-artifact@v4` uploading
     `ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework` as the
     `OlcRTCMobile-xcframework` artifact (`if-no-files-found: error`).
- Added a top-level `.gitattributes` forcing LF line endings for
  `*.sh`, `*.yml`, `*.yaml`, and `Makefile`. Without this, Windows
  checkouts of `build-gomobile-ios.sh` would write CRLF and
  `/usr/bin/env bash` on the macOS runner would refuse the shebang
  (`bad interpreter: No such file or directory`). The committed blob
  for `scripts/build-gomobile-ios.sh` is LF-only with mode `100755`.
- `ios/OlcRTCClient/README.md` gained a section explaining that the
  framework is generated by CI / the script, lives at
  `ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework`, is
  `.gitignore`d, and is not yet wired into `project.yml`.
- **Not done in this step**, intentionally: wiring the framework into
  `project.yml`, calling Go from `LocalProxyManager` / the extension,
  IPA packaging, Go core changes, signing.

---

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
- **Gomobile bind risks (specific to the new `Gomobile iOS Bind`
  workflow):**
  - **Upstream Go version availability.** `third_party/olcrtc/go.mod`
    currently requests `go 1.26.3`. If `actions/setup-go@v5` cannot
    fetch that toolchain (not yet released, or not yet in the runner
    catalog), the workflow fails at the `Setup Go` step. Per the task
    brief, we **do not** silently downgrade and **do not** edit
    upstream `go.mod` — surface the exact error and bring it back to
    chat. The fix is either (a) wait for the toolchain to be
    available, or (b) bump the upstream `fix/all` branch to a Go
    version the runner has, and bump the submodule pointer here.
  - **`gomobile bind -target=ios` symbol limits.** The Go core imports
    several packages (`livekit/protocol`, `livekit/server-sdk-go`,
    `pion/webrtc`, etc.). gomobile/gobind cannot bind every Go
    construct (generics, channels of complex types, methods on
    unexported types, etc.); failures here surface during `bind`, not
    `init`. If `bind` fails, the right move is a thin
    iOS-friendly subset in the upstream `./mobile` package — **upstream
    change, not local Go edits**.
  - **CRLF on `build-gomobile-ios.sh`.** Mitigated by
    `.gitattributes` (`*.sh text eol=lf`) and verified blob bytes at
    commit time. If a future contributor edits the script from
    Windows without honouring `.gitattributes`, the macOS runner will
    fail with `/usr/bin/env: 'bash\r': No such file or directory`.
  - **`gomobile init` on `macos-latest`.** It downloads NDK-related
    bits even for an iOS-only build in some versions. If the step
    becomes flaky or slow, switch to `gomobile init -ndk skip` (or
    omit `init` once iOS-only init becomes a no-op in newer
    gomobile releases).
  - **xcframework artifact size.** Static archives for arm64 + x86_64
    simulator + arm64 device can run into the hundreds of MB.
    `actions/upload-artifact@v4` accepts this, but expect the upload
    step to dominate the workflow runtime.

---

## Next

Ordered by intended sequence. Each item should be a separate change /
session so the diff stays reviewable.

1. **Refresh `docs/ai/GOMOBILE_BINDINGS.md` from the green
   `Gomobile iOS Bind` artifact.** Download
   `gomobile-inspection-report` from the run that includes the new
   inspection step, paste the verbatim framework / module / symbol
   names into `GOMOBILE_BINDINGS.md`, commit. **Do not** wire Swift
   to anything until this file records the real names.
2. **Wire Local Proxy Mode to the real gomobile API.** With the
   refreshed bindings doc in hand, update `project.yml` to add
   `OlcRTCMobile.xcframework` as a dependency for `OlcRTCClient`
   (and, where it links cleanly under
   `APPLICATION_EXTENSION_API_ONLY: YES`, for
   `PacketTunnelProvider`). Replace `MockOlcRTCService` calls in
   `LocalProxyManager` with `Start` / `Stop` / `Check` / `Ping` /
   `IsRunning` / `WaitReady` / `SetLogWriter` from the real
   bindings. The scaffold workflow grows (or a sibling
   `ios-build.yml` workflow appears) that runs the gomobile bind
   before `xcodegen generate`.
3. **Profile store in App Group container.** Move `ProfileStore` from
   the app sandbox to the shared App Group so the extension can read
   profiles. Decide whether `keyHex` moves to Keychain — write a new
   ADR before coding. Re-attaching the entitlements happens here
   only if a signing identity is available; otherwise the App Group
   path stays "future-signing".
4. **Subscription import** per `docs/sub.md`. HTTPS fetch + parse
   + merge into the shared profile store.
5. **VPN Mode plumbing.** Real `NETunnelProviderManager` install /
   enable / observe in `VPNManager`. In the extension, configure
   `NEPacketTunnelNetworkSettings`, bring up the Go runtime against
   the selected `PacketTunnelConfig`, bridge `NEPacketTunnelFlow`.
   Real-device runtime is still gated on signing — that is fine for
   this step.
6. **Sanitized log view in-extension.** Currently `LogSanitizer` is
   compiled into both targets but only the app exposes a UI. Once
   the extension produces real logs, mirror them into the App
   Group so the app UI can show them.
7. **Unsigned `.ipa` packaging step.** Once gomobile is wired,
   extend the build workflow to package an unsigned `.ipa` and
   upload it as a workflow artifact (ADR-0008).
8. **(Future, gated on signing)** A separate signed-build pipeline
   once an Apple Developer account, provisioning profile, and
   `NetworkExtension` entitlement are available. New ADR before
   any code lands. Reattaching the `.entitlements` files happens
   here.

Do not skip ahead — earlier steps unblock later ones, and the
constraints in `CLAUDE.md` will reject shortcuts that try to.
