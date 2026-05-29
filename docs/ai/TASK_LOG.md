# TASK_LOG.md

Running log for the iOS client track. Append to the appropriate section; do
not rewrite history. The next Claude session reads this to pick up cold, so
write entries that make sense without the surrounding chat.

Date format: `YYYY-MM-DD`. Each entry should answer **what** changed and
**why**, not narrate process.

---

### 2026-05-29 — Probe v6: hard C relocation anchors + `optnone`

- v5's diagnosis (entry directly below) was that ld_prime LTO +
  `-Os` folded the v5 anchor body into a no-op: the calls to
  `MobileIsRunning` (return cast to `(void)`) and
  `MobileSetDebug(NO)` (void return) had no LTO-visible side
  effect, so they were eliminated even though
  `__attribute__((used))` kept the **symbol**.
  `__attribute__((used))` protects the symbol, not the
  statements inside the body. Linker-only and symbol-only
  mitigations (`-Wl,-u`, `-needed_framework`,
  `__attribute__((used))`) have been exhausted. v6 moves the
  gomobile references out of the body's call instructions and
  into Mach-O **data relocations** that LTO cannot fold.
- File rewritten:
  `ios/OlcRTCClient/Sources/PacketTunnelProvider/GomobileExtensionLinkAnchor.m`.
  The new shape combines three independent guarantees, any one
  of which would on its own keep the OlcRTCMobile link edge:

  ```objc
  typedef BOOL (*OlcRTCMobileIsRunningFn)(void);
  typedef void (*OlcRTCMobileSetDebugFn)(BOOL);

  __attribute__((used))
  static volatile BOOL OlcRTCGomobileBoolSink = NO;

  __attribute__((used))
  static volatile OlcRTCMobileIsRunningFn OlcRTCGomobileIsRunningPtr = MobileIsRunning;

  __attribute__((used))
  static volatile OlcRTCMobileSetDebugFn OlcRTCGomobileSetDebugPtr = MobileSetDebug;

  __attribute__((used, noinline, optnone))
  void OlcRTCExtensionGomobileLinkAnchor(void) {
      OlcRTCMobileIsRunningFn isRunning =
          (OlcRTCMobileIsRunningFn)OlcRTCGomobileIsRunningPtr;
      OlcRTCMobileSetDebugFn setDebug =
          (OlcRTCMobileSetDebugFn)OlcRTCGomobileSetDebugPtr;
      BOOL running = isRunning();
      OlcRTCGomobileBoolSink = running;
      setDebug(OlcRTCGomobileBoolSink);
  }
  ```

  - **Guarantee 1 — data relocations.** The two
    function-pointer initializers force clang to emit Mach-O
    relocations against `_MobileIsRunning` and `_MobileSetDebug`
    in the data segment. Those relocations are not call
    instructions; LTO has no notion of "the result of this
    pointer is unused" and cannot fold them away. ld must
    resolve them against `OlcRTCMobile.framework`, which keeps
    `LC_LOAD_DYLIB` for the framework regardless of whether
    anything ever calls through the pointers.
  - **Guarantee 2 — volatile observable behaviour.** Every read
    and write to a `volatile`-qualified object is observable
    behaviour under the C standard. Loading the function
    pointers, calling through them, writing the result into
    `OlcRTCGomobileBoolSink`, and reading it back to pass to
    `setDebug` form a chain of observable accesses; the
    optimizer cannot prove the chain is dead.
  - **Guarantee 3 — `optnone` on the anchor.** clang accepts
    `optnone` (since 3.5; Apple clang in Xcode 16.4 supports
    it) to compile a function at -O0 regardless of the file's
    optimization level. The attribute survives into LTO IR and
    keeps the body's instructions intact.
  - `__attribute__((used))` on each `static` variable prevents
    the compiler from removing the variable itself even if no
    code reads it. `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor`
    in the extension target's `OTHER_LDFLAGS` keeps the anchor
    function symbol in the final binary regardless of Swift
    references.
- `ios/OlcRTCClient/project.yml`. Extension target's
  `OTHER_LDFLAGS` becomes
  `$(inherited) -lresolv -Wl,-u,_OlcRTCExtensionGomobileLinkAnchor`.
  `-Wl,-needed_framework,OlcRTCMobile` is **removed** for v6:
  v4 already proved `-needed_framework` loses to the trailing
  `-framework OlcRTCMobile` injected by the dependency on this
  toolchain, and v6 wants the verdict to come purely from the
  C-side relocation anchors and the implicit `-framework
  OlcRTCMobile` from the dependency. With `-needed_framework`
  in the mix a green v6 would have been ambiguous about which
  layer carried the link edge; without it, a green v6 means
  the C anchors did the work.
- `APPLICATION_EXTENSION_API_ONLY = YES` remains set on the
  extension target. Code signing stays disabled. Entitlements
  stay detached. `OlcRTCMobile.xcframework` dependency on the
  extension target stays `embed: false, codeSign: false,
  link: true`. `PacketTunnelProvider.startTunnel` still fails
  fast with `notWiredYet`. The Swift-side
  `GomobileExtensionProbe.swift` and `_gomobileLinkAnchor`
  stored property are kept as harmless documentation
  landmarks; v6 does not depend on them.
- `.github/workflows/packet-tunnel-gomobile-probe.yml`
  confirm step is restructured into four numbered sections so
  a future failure points at the exact layer that ate the
  references:
  - **A. Final binary diagnostics** — full `otool -L`,
    `nm -u | grep Mobile(IsRunning|SetDebug)`,
    `nm | grep OlcRTCExtensionGomobileLinkAnchor|OlcRTCGomobile`.
  - **B. Intermediate object diagnostics** — walks every `.o`
    under `build/DerivedData/**/PacketTunnelProvider.build/**`
    and prints both `nm` and `nm -u` lines matching
    `Mobile(IsRunning|SetDebug)|OlcRTCExtensionGomobileLinkAnchor|OlcRTCGomobile`,
    plus a final `obj_count` and `obj_has_mobile_refs`
    aggregate.
  - **C. Linker command** — the captured Ld step from
    `build/xcodebuild.log`, unchanged from v5.
  - **D. Result classification** — combines the signals
    above into one of:
    - `PASS` — `otool -L` lists OlcRTCMobile **and** final
      binary has Mobile* undef refs;
    - `PASS-WEAK` — `otool -L` lists OlcRTCMobile but no
      final-binary Mobile* undef (the link edge is real but
      the body's calls were still folded; flagged because v6
      is supposed to keep both);
    - `FAIL-STRIPPED-BEFORE-LINK` — no Mobile* undef in any
      `.o` (references died upstream of ld);
    - `FAIL-STRIPPED-AFTER-LINK` — `.o` files have Mobile*
      undef but final binary has no OlcRTCMobile load command
      (ld / LTO native-code stage stripped them);
    - `FAIL-OTHER` — none of the above; see the printed
      signals.
  `FAIL-COMPILE` and `FAIL-LINK` are not emitted by this step
  — those would have aborted the previous (build) step with a
  clang or ld diagnostic. The remaining classes split exactly
  the live failure space.
- Acceptance criterion (probe v6): the workflow runs green
  AND the `D. Result classification` line reads `PASS`
  (not `PASS-WEAK`) — `otool -L` lists
  `Frameworks/OlcRTCMobile.framework/OlcRTCMobile`, the final
  binary's `nm -u` shows at least one of
  `_MobileIsRunning` / `_MobileSetDebug`, and at least one
  intermediate `.o` already carries a Mobile* undef. The
  extension still compiles cleanly under
  `APPLICATION_EXTENSION_API_ONLY = YES` and code signing
  stays disabled. No IPA, no app tests, no extension runtime,
  no Go core changes.

---

### 2026-05-29 — Probe v5 result: C anchor symbol survived, but its `Mobile*` calls were stripped

- Run:
  [`Packet Tunnel Gomobile Probe` 26627159196](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26627159196)
  on commit
  [`9045db6`](https://github.com/artpm4250-png/olcrtc-ios/commit/9045db6).
  Conclusion: **failure** at the same confirm step as v4 — the
  build itself succeeded, including compilation of the new
  `Sources/PacketTunnelProvider/GomobileExtensionLinkAnchor.m`,
  but the post-build assertions tripped.
- Direct evidence captured by the v5 confirm step
  (`gh run view 26627159196 --log-failed`):
  - `nm "$APPEX/PacketTunnelProvider" | grep _OlcRTCExtensionGomobileLinkAnchor`
    →
    `0000000100004000 T _OlcRTCExtensionGomobileLinkAnchor`.
    The C anchor symbol **is** defined in the extension binary's
    text segment. `__attribute__((used))` +
    `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor` did their job —
    the function is in the final image.
  - `nm -u "$APPEX/PacketTunnelProvider" | grep -E 'Mobile(IsRunning|SetDebug)'`
    → `(none — no MobileIsRunning / MobileSetDebug undef found)`.
    The two calls inside the C function body produced **zero**
    surviving undefined references in the extension binary.
  - `otool -L "$APPEX/PacketTunnelProvider"` → still no
    `Frameworks/OlcRTCMobile.framework/OlcRTCMobile` line.
  - The captured Ld step shows the linker received both the new
    flag and the kept v4 flag plus the dependency-injected
    framework reference:
    `… -lresolv -Wl,-needed_framework,OlcRTCMobile -Wl,-u,_OlcRTCExtensionGomobileLinkAnchor -framework OlcRTCMobile -o …PacketTunnelProvider`.
    `-dead_strip` is also present (default for Release).
- Diagnosis. Build settings stayed correct
  (`APPLICATION_EXTENSION_API_ONLY = YES` confirmed in
  `project.yml:108`; signing disabled; entitlements detached).
  The v5 strategy moved the anchor out of Swift's reach — and
  Swift WMO is no longer the cause: clang did compile
  `GomobileExtensionLinkAnchor.m` (the symbol's address proves
  the .o reached the linker). What now strips the references is
  one layer further down: by default for Release `iphoneos` the
  Xcode 16.4 link step runs **LTO** (the
  `-Xlinker -object_path_lto -Xlinker …PacketTunnelProvider_lto.o`
  flag is in the captured Ld command line, and `_lto.o` exists
  on the runner). With LTO + `-Os` + ARC, ld_prime appears to
  fold the two-call body of `OlcRTCExtensionGomobileLinkAnchor`
  into something equivalent to a single `ret` — the C function
  remains, but its calls to `MobileIsRunning` (return value
  cast to `(void)`, no observable use) and
  `MobileSetDebug(NO)` (void return, no observable use) are
  treated as dead and removed. With no surviving call sites
  for `Mobile*`, ld then dead-strips the OlcRTCMobile load
  command exactly as it did in v4 — `-needed_framework` once
  again loses to the trailing `-framework OlcRTCMobile`
  injected by the dependency on this toolchain.
  `__attribute__((used))` only protects the **symbol**, not the
  body's individual statements; once optimization runs over the
  body, the protection ends.
- Implication for the next probe. The fix is to make the calls
  *observable* in the C-standard sense so neither LLVM's IR
  optimizer nor ld's LTO can prove them dead. Concretely, the
  next iteration should either (a) annotate the anchor with
  `__attribute__((optnone))` so the function body is compiled
  unoptimized, (b) write the result of `MobileIsRunning()` to a
  `volatile`-qualified file-scope variable and call
  `MobileSetDebug` through a `volatile`-qualified function
  pointer (volatile accesses are observable behavior and cannot
  be elided), or (c) take the addresses of `MobileIsRunning` and
  `MobileSetDebug` as the initializers of static const data
  visible through the same anchor symbol — the resulting Mach-O
  relocations are not subject to dead-call elimination.
  Linker-only mitigations (`-Wl,-u`, `-needed_framework`) have
  been exhausted; further attempts at that layer will not move
  the result.
- Files unchanged on disk relative to `9045db6`:
  - `ios/OlcRTCClient/Sources/PacketTunnelProvider/GomobileExtensionLinkAnchor.m`
    — unchanged.
  - `ios/OlcRTCClient/project.yml` — unchanged
    (`APPLICATION_EXTENSION_API_ONLY: YES` still on,
    `OTHER_LDFLAGS: $(inherited) -lresolv -Wl,-needed_framework,OlcRTCMobile -Wl,-u,_OlcRTCExtensionGomobileLinkAnchor`,
    framework dependency `embed: false / codeSign: false / link: true`,
    signing disabled, entitlements detached).
  - `.github/workflows/packet-tunnel-gomobile-probe.yml` —
    unchanged from `9045db6` (full `otool -L`, Mobile-undef
    grep, anchor-symbol diagnostic, captured Ld step, both
    hard assertions).
  - `Sources/PacketTunnelProvider/PacketTunnelProvider.swift` and
    `Sources/PacketTunnelProvider/GomobileExtensionProbe.swift`
    — unchanged. `startTunnel` still fails fast with
    `notWiredYet`.
- Probe v5 ends here. The next probe (v6) should address the
  LTO-elision diagnosis above; no code or workflow changes
  follow this result.

---

### 2026-05-29 — Probe v5: ObjC/C anchor + `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor`

- v4's diagnosis (see entry directly below) was that the link
  edge to `OlcRTCMobile` disappears because the Swift anchor
  (`private let _gomobileLinkAnchor: Bool = GomobileExtensionProbe.touch()`)
  is eliminated by `-O -whole-module-optimization` *before* the
  linker ever sees a reference to `MobileIsRunning` /
  `MobileSetDebug`. Linker-side flags (`-u`, `-needed_framework`)
  cannot rescue references that never reach the linker. v5 fixes
  the *probe*, not the linker — the anchor moves out of Swift's
  reach.
- New file:
  `ios/OlcRTCClient/Sources/PacketTunnelProvider/GomobileExtensionLinkAnchor.m`.
  Imports `<Foundation/Foundation.h>` and
  `<OlcRTCMobile/OlcRTCMobile.h>`, defines a single C function:

  ```objc
  __attribute__((used))
  void OlcRTCExtensionGomobileLinkAnchor(void) {
      (void)MobileIsRunning();
      MobileSetDebug(NO);
  }
  ```

  `__attribute__((used))` keeps clang from removing the function
  body as unused at the object-file level. Both calls are the
  safest pair on the gomobile surface — pure status read +
  configure-only flag flip — so the probe still does not start
  any olcRTC runtime, does not open sockets, and is not invoked
  from `PacketTunnelProvider.startTunnel` (which still fails
  fast with `notWiredYet`).
- `ios/OlcRTCClient/project.yml`, extension target's
  `OTHER_LDFLAGS` becomes
  `$(inherited) -lresolv -Wl,-needed_framework,OlcRTCMobile -Wl,-u,_OlcRTCExtensionGomobileLinkAnchor`.
  `-Wl,-u,_OlcRTCExtensionGomobileLinkAnchor` tells ld to keep
  the C anchor's symbol in the final binary regardless of who
  references it; once that function is in the binary, its body
  carries genuine undefined references to `_MobileIsRunning` and
  `_MobileSetDebug`, which forces ld to keep the
  `LC_LOAD_DYLIB` for `OlcRTCMobile`. The
  `-Wl,-needed_framework,OlcRTCMobile` from v4 is kept as
  belt-and-suspenders; with the C-side undefs present it is
  functionally redundant, but its absence would make a
  regression to v4 territory silent.
- `APPLICATION_EXTENSION_API_ONLY = YES` remains set on the
  extension target. Code signing stays disabled
  (`CODE_SIGNING_ALLOWED = NO`, `CODE_SIGN_IDENTITY = ""`,
  `CODE_SIGNING_REQUIRED = NO`). Entitlements stay detached.
  `OlcRTCMobile.xcframework` dependency on the extension target
  is unchanged (`embed: false, codeSign: false, link: true`).
  The Swift-side `GomobileExtensionProbe.swift` and
  `_gomobileLinkAnchor` stored property are kept as harmless
  documentation landmarks — they no longer carry the link
  guarantee, but removing them now would muddy the diff.
- `.github/workflows/packet-tunnel-gomobile-probe.yml` confirm
  step now:
  - tees `xcodebuild` output to `build/xcodebuild.log` so the Ld
    invocation can be quoted directly in the assertion step;
  - prints the full `otool -L` output;
  - prints `nm -u | grep -E 'Mobile(IsRunning|SetDebug)'`;
  - prints the defined-symbol line for
    `_OlcRTCExtensionGomobileLinkAnchor` from the extension
    binary (diagnostic for whether the C anchor itself
    survived);
  - extracts and prints the `Ld …PacketTunnelProvider.appex…`
    block from `build/xcodebuild.log` (best-effort);
  - **hard-fails** if `otool -L` does not list
    `OlcRTCMobile.framework/OlcRTCMobile`;
  - **hard-fails** if `nm -u` produces no
    `MobileIsRunning` / `MobileSetDebug` line. The v4-era
    "Mobile-prefixed undef count is a diagnostic only" stance
    is reverted — under the v5 strategy, those undefs are the
    direct evidence that the link edge is real, so they must be
    present.
- Acceptance criterion (probe v5): the workflow runs green AND
  the confirm step prints both
  `Frameworks/OlcRTCMobile.framework/OlcRTCMobile` (in `otool -L`)
  and at least one of `_MobileIsRunning` / `_MobileSetDebug` (in
  `nm -u`). The extension still compiles cleanly under
  `APPLICATION_EXTENSION_API_ONLY = YES` and code signing stays
  disabled. No IPA, no app tests, no extension runtime, no Go
  core changes.

---

### 2026-05-29 — Probe v4 result: `-needed_framework` did **not** survive ld_prime + WMO

- Run:
  [`Packet Tunnel Gomobile Probe` 26606165919](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26606165919)
  on commit
  [`f3e4933`](https://github.com/artpm4250-png/olcrtc-ios/commit/f3e4933).
  Conclusion: **failure**. The build itself succeeded — the
  extension compiled cleanly and the linker invocation completed
  without errors. The CI **assertion step** failed.
- Verified from the Xcode log: the Ld step for
  `PacketTunnelProvider.appex/PacketTunnelProvider` invoked clang
  with **both** `-Wl,-needed_framework,OlcRTCMobile` (from the
  target's `OTHER_LDFLAGS`) **and** `-framework OlcRTCMobile`
  (from the XcodeGen dependency `link: true`). `-dead_strip` was
  also passed. Despite that, the resulting binary's load commands
  contain no `Frameworks/OlcRTCMobile.framework/OlcRTCMobile` line
  (full `otool -L` output: only `libresolv`, Foundation, libobjc,
  libSystem, CoreFoundation, NetworkExtension, Security, the swift
  runtime libs). `nm -u "$APPEX/PacketTunnelProvider" | grep -c Mobile = 0` —
  not a single `Mobile`-prefixed undefined symbol survived into the
  extension binary.
- `APPLICATION_EXTENSION_API_ONLY = YES` remained set throughout —
  no diagnostic from clang or swiftc about extension-restricted
  API; the per-target build setting is unchanged from probe v3.
  Code signing stayed disabled (`CODE_SIGNING_ALLOWED = NO`,
  `CODE_SIGN_IDENTITY = ""`) and entitlements remained detached.
- Diagnosis. The empty `Mobile`-prefixed undef count is the
  smoking gun: by the time the linker runs, the Swift compile
  output for the extension target contains **zero** references
  to any `Mobile*` symbol from `OlcRTCMobile`. Probe v2 added
  the stored property
  `private let _gomobileLinkAnchor: Bool = GomobileExtensionProbe.touch()`
  on `final class PacketTunnelProvider`, but at `-O
  -whole-module-optimization` the Swift optimizer can prove
  nothing reads that `private let`, so it elides the storage and
  — with it — the initializer's `MobileSetDebug(false)` and
  `MobileIsRunning()` calls. With no surviving symbol reference,
  ld_prime's `-dead_strip` then removes the `LC_LOAD_DYLIB` for
  `OlcRTCMobile` even though `-needed_framework` was supplied
  earlier on the same command line: the trailing `-framework
  OlcRTCMobile` (XcodeGen-injected) re-registers the same
  framework as a regular reference, and on Xcode 16.4's ld_prime
  the regular registration appears to win — when the regular
  reference has zero surviving uses, the framework is stripped
  outright. The Swift-level elision is the upstream cause; the
  `-needed_framework` shadowing is the downstream cause.
- What this means. The probe's *narrow* original goal —
  "extension target compiles and the linker invocation completes
  cleanly with `APPLICATION_EXTENSION_API_ONLY = YES`
  against `OlcRTCMobile.xcframework`" — was already proven by
  probe v1
  ([26600505401](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26600505401),
  green on `bdf0c3d`). The *stricter* goal added in v2-v4 —
  "and the resulting binary actually carries the `OlcRTCMobile`
  load command" — is not yet proven. Linker-side flags alone
  are not enough on this toolchain; the next probe needs to
  defeat the **Swift-side** dead-strip (e.g. expose the
  references through `@objc dynamic` storage on the principal
  class, or via an `@_used` `@_cdecl` top-level function in the
  probe file) so the extension's object code carries surviving
  references to `MobileSetDebug` / `MobileIsRunning` before the
  linker ever sees the input.
- Files unchanged on disk relative to `f3e4933`:
  - `ios/OlcRTCClient/project.yml` — extension target still
    `APPLICATION_EXTENSION_API_ONLY: YES`, signing disabled,
    entitlements not attached, framework dependency `embed:
    false / codeSign: false / link: true`,
    `OTHER_LDFLAGS: $(inherited) -lresolv -Wl,-needed_framework,OlcRTCMobile`.
  - `Sources/PacketTunnelProvider/GomobileExtensionProbe.swift` —
    `enum GomobileExtensionProbe { @discardableResult static
    func touch() -> Bool { MobileSetDebug(false); return
    MobileIsRunning() } }` under `#if canImport(OlcRTCMobile)`.
    Confirmed compiled (visible in
    `SwiftCompile normal arm64 Compiling … GomobileExtensionProbe.swift …`).
  - `Sources/PacketTunnelProvider/PacketTunnelProvider.swift` —
    `private let _gomobileLinkAnchor: Bool = GomobileExtensionProbe.touch()`
    on `final class PacketTunnelProvider`.
  - `.github/workflows/packet-tunnel-gomobile-probe.yml` — confirm
    step still hard-fails on missing `OlcRTCMobile.framework/OlcRTCMobile`
    in `otool -L`; `Mobile`-prefixed undef count is a diagnostic
    only.
- Probe v4 ends here. No code or workflow changes follow this
  result; the next probe (v5) should be opened in a new entry
  with its own commit.

---

### 2026-05-29 — Probe v4: force the load command via `-needed_framework`

- Probe v3 (`f599e12`) replaced the Swift-side anchor with
  `-Wl,-u,_MobileIsRunning` in the extension's `OTHER_LDFLAGS`.
  The run
  ([26605818266](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26605818266))
  confirmed the flag landed in the actual clang link command
  (visible in the build log at the
  `Ld .../PacketTunnelProvider.appex/PacketTunnelProvider` step),
  but the confirm step still failed: `otool -L` showed no
  `OlcRTCMobile.framework/OlcRTCMobile`, and the `Mobile`-prefixed
  undef count remained zero. ld64 on iOS 18.5 SDK appears to drop
  `-u <symbol>`-added undefs during `-dead_strip` if no
  non-stripped reference survives — `-u` alone is not enough on
  this toolchain.
- Fix: use ld64's `-needed_framework` directive instead. It is
  Apple's explicit "keep the `LC_LOAD_DYLIB` for this framework
  even if dead-stripping finds no surviving references"
  instruction, designed precisely for this case (framework that
  must be linked but whose symbols are not yet referenced by the
  consumer). The extension target's `OTHER_LDFLAGS` becomes:
  `$(inherited) -lresolv -Wl,-needed_framework,OlcRTCMobile`.
- Kept (intentionally):
  - `Sources/PacketTunnelProvider/GomobileExtensionProbe.swift`
    and `PacketTunnelProvider._gomobileLinkAnchor` stored
    property. With `-needed_framework`, the linker keeps the load
    command without depending on a Swift-side reference — but the
    Swift anchor still gives the next reader an obvious "here is
    where the extension touches gomobile" landmark and forces a
    minimal Swift compile-time check that the gomobile symbols
    are visible from inside the extension target. If
    `-needed_framework` is ever removed by mistake, the Swift
    anchor at least keeps the *compile* path alive.
  - All other unsigned / no-IPA / no-app-tests scope from probe
    v1–v3 (`APPLICATION_EXTENSION_API_ONLY = YES` untouched,
    code signing disabled, entitlements detached).
- Updated `.github/workflows/packet-tunnel-gomobile-probe.yml`:
  - The "extension binary must reference `OlcRTCMobile.framework`
    in its load commands" assertion stays a hard failure (this is
    the real proof of the link edge).
  - The "Mobile-prefixed undef count ≥ 1" assertion is **demoted
    to a diagnostic**. With `-needed_framework`, the load command
    is kept regardless of whether any symbol references the
    framework's exports — so a zero count there is no longer a
    bug. Print the number for context but do not fail on it.
- Acceptance criterion (probe v4): the
  `Packet Tunnel Gomobile Probe` workflow runs green AND the
  confirm step prints
  `Frameworks/OlcRTCMobile.framework/OlcRTCMobile` somewhere in
  `otool -L`'s output. The Mobile-prefixed undef count is a
  diagnostic. The extension still compiles cleanly under
  `APPLICATION_EXTENSION_API_ONLY = YES`.

---

### 2026-05-29 — Probe v3: force the link edge via `-Wl,-u,_MobileIsRunning`

- Probe v2 (`9688ed8`) added a stored-property anchor on
  `PacketTunnelProvider` and turned the CI confirm-step assertions
  into hard failures. The run
  ([26602034273](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26602034273))
  passed the build step but **failed** the confirm step exactly as
  intended — `otool -L` had no `OlcRTCMobile.framework`,
  `nm -u | grep -c Mobile = 0`. Reading the link command in the
  log:
  ```
  clang ... -fapplication-extension ... -dead_strip ...
        -lresolv -framework OlcRTCMobile ...
  ```
  shows that even with the Swift stored-property anchor, clang's
  `-dead_strip` (always on for `iphoneos` Release) saw no
  surviving reference into `OlcRTCMobile`'s symbol table from the
  extension's object files (Swift whole-module / LTO eliminated
  the unused `_gomobileLinkAnchor` body). With nothing referenced,
  the linker dropped the `LC_LOAD_DYLIB` for `OlcRTCMobile.framework`.
- Fix: extend the extension target's `OTHER_LDFLAGS` from
  `$(inherited) -lresolv` to
  `$(inherited) -lresolv -Wl,-u,_MobileIsRunning`. The `-u
  <symbol>` ld(1) flag forces the named Mach-O symbol to be
  treated as an undefined import — which makes the linker keep
  the load command for the framework that exports it. This is a
  link-time directive, so Swift / LTO can't optimize it away.
  - `_MobileIsRunning` is the C-exported name of the gomobile
    `MobileIsRunning()` symbol (see
    `docs/ai/GOMOBILE_BINDINGS.md` §2). It is configure /
    read-only and does not start any network work, matching the
    probe's "compile + link, no runtime" scope.
  - The Swift-side anchor (`GomobileExtensionProbe.touch()` +
    `_gomobileLinkAnchor` stored property on
    `PacketTunnelProvider`) is intentionally kept. With `-u` in
    place, dead-stripping can no longer affect the link edge, but
    the Swift anchor still gives the next reader a place to look
    when grepping for "extension references gomobile" — and if
    `-u` is ever removed by mistake, the Swift anchor at least
    forces a single specialization to compile, which makes the
    failure mode obvious (zero count → assertion fires).
- This change is to the extension target's build settings only;
  no source change, no Swift compile-flag change, no Go-core
  change, no signing, no entitlement attachment, no IPA
  packaging difference. The host-app `iOS App + Gomobile Build`
  workflow is untouched (the host app already references the
  framework heavily via `LocalProxyManager` →
  `RealOlcRTCService`, so its link edge was never in doubt).
- Acceptance criterion (probe v3): same as probe v2 — the
  `Packet Tunnel Gomobile Probe` workflow runs green AND the
  `Confirm extension binary actually linked against OlcRTCMobile`
  step shows `OlcRTCMobile.framework/OlcRTCMobile` in
  `otool -L` plus a non-zero `Mobile`-prefixed undef count. The
  difference vs v2 is that the link edge now survives
  whole-module Swift optimization.

---

### 2026-05-29 — Probe v2: anchor the OlcRTCMobile link edge against dead-code stripping

- Followup on the `packet-tunnel-gomobile-probe` first run
  ([run 26600505401](https://github.com/artpm4250-png/olcrtc-ios/actions/runs/26600505401)),
  which went green but exposed that **`xcodebuild build` succeeding
  is not the same as the extension actually linking against
  `OlcRTCMobile.xcframework`**:
  - The build-step xcodebuild produced
    `Release-iphoneos/PacketTunnelProvider.appex` clean.
  - `otool -L` on the extension binary did **not** list
    `OlcRTCMobile.framework/OlcRTCMobile`.
  - `nm -u <bin> | grep -c Mobile` returned **0** — i.e. zero
    undefined symbol references to anything `Mobile`-prefixed.
  - Root cause: the previous probe lived in a static method on an
    enum (`GomobileExtensionProbe.touch()`) that was never called
    from any reachable code path in the extension. Swift's
    whole-module optimization + dead-code stripping pruned the
    method, the `import OlcRTCMobile` consumer disappeared with
    it, and the linker had no reason to record a load command for
    the framework. The build still passed because the import
    itself was satisfied — the extension never depended on any
    symbol that wasn't otherwise reachable.
- Goal of this followup: make the probe actually **prove the link
  edge**, and make CI fail the probe if a future change
  regresses it.
- Changes in
  `ios/OlcRTCClient/Sources/PacketTunnelProvider/PacketTunnelProvider.swift`:
  - Added a stored property
    `private let _gomobileLinkAnchor: Bool = GomobileExtensionProbe.touch()`
    gated on `#if canImport(OlcRTCMobile)`. The principal class
    `PacketTunnelProvider` is reachable from `NSExtensionPrincipalClass`
    via the Obj-C runtime, so its stored-property initializers
    run on every instance — which forces the linker to keep
    `GomobileExtensionProbe.touch()` and the
    `MobileSetDebug` / `MobileIsRunning` symbols it references.
  - `startTunnel` body is **unchanged** — it still calls
    `completionHandler(StubError.notWiredYet)` and runs no
    olcRTC code. No `MobileStart*` / `MobileCheck` / `MobilePing`
    call from the extension.
  - Updated the file-header doc comment to say the extension now
    links against `OlcRTCMobile.xcframework` via the probe anchor
    (configure / read-only symbols only) while still being a
    runtime stub.
- Changes in `.github/workflows/packet-tunnel-gomobile-probe.yml`:
  - Renamed `Confirm extension binary actually linked` →
    `Confirm extension binary actually linked against OlcRTCMobile`
    and converted the previously-diagnostic `otool -L` /
    `nm -u | grep -c Mobile` output into **hard assertions**:
    1. `otool -L "$APPEX/PacketTunnelProvider"` must contain a
       line matching `OlcRTCMobile.framework/OlcRTCMobile`. If
       not, the linker did not pull in the framework — fail with
       a "probe likely got dead-code-stripped" hint.
    2. `nm -u "$APPEX/PacketTunnelProvider" | grep -c "Mobile"`
       must be `>= 1` (we expect at least
       `MobileIsRunning` and `MobileSetDebug` from the probe).
    This way a future change that, e.g., removes the
    `_gomobileLinkAnchor` stored property will turn this step red
    instead of silently going green again.
  - All other unsigned / no-IPA / no-app-tests scope from the v1
    probe preserved (`APPLICATION_EXTENSION_API_ONLY = YES`
    untouched, code signing disabled, entitlements detached,
    `xcodebuild` flags identical).
- Doc bookkeeping:
  - This TASK_LOG entry records the dead-code-stripping discovery
    so the next session understands why `_gomobileLinkAnchor`
    exists and does not "clean it up".
  - `docs/ai/GOMOBILE_BINDINGS.md` "Extension-target linking
    (probe in progress)" subsection from yesterday already lists
    "Other `APPLICATION_EXTENSION_API_ONLY` violations" and
    "undefined symbols at link time" as expected failure modes;
    the dead-code-stripping mode is an additional one, recorded
    in-line in `PacketTunnelProvider.swift` and in this entry.
- Acceptance criterion (probe v2): the
  `Packet Tunnel Gomobile Probe` workflow goes green AND the
  `Confirm extension binary actually linked against OlcRTCMobile`
  step shows `OlcRTCMobile.framework/OlcRTCMobile` in
  `otool -L` and a non-zero `Mobile`-prefixed undef count.
- **Not done in this step**, intentionally: any real VPN runtime
  wiring, any `MobileStart*` call from the extension, any
  signing, any entitlement attachment, any Go-core change, any
  new feature, any change to the host-app
  `iOS App + Gomobile Build` workflow or to the unsigned IPA
  artifact.

---

### 2026-05-28 — PacketTunnelProvider gomobile compile/link probe

- Branch: `packet-tunnel-gomobile-probe`. **Probe only**: this step
  introduces no runtime behavior change and no new feature. The
  extension still fails fast with `VPNManagerError.notWiredYet`. We
  do NOT call `MobileStart` / `MobileStartWithTransport` /
  `MobileCheck` / `MobilePing` from the extension. We do NOT
  configure `NEPacketTunnelNetworkSettings` or touch
  `NEPacketTunnelFlow`. We do NOT add signing or attach
  entitlements. No IPA packaging in this workflow.
- Goal: answer one question — can the `PacketTunnelProvider`
  extension target link against `OlcRTCMobile.xcframework` under
  `APPLICATION_EXTENSION_API_ONLY = YES`, with code signing
  disabled, on `macos-latest`? Knowing this is a Milestone-3
  prerequisite (`docs/ROADMAP.md`). The runtime portion of
  Milestone 3 stays gated on Milestone 2 (signed build), but the
  link probe is unblocked today and can run from CI alone.
- Changes in `ios/OlcRTCClient/project.yml`:
  - `PacketTunnelProvider` target now adds
    `Frameworks/OlcRTCMobile.xcframework` as a framework dependency
    with `embed: false, codeSign: false, link: true`.
    - `link: true` is what we actually want — the symbols become
      available to the extension's compile/link step.
    - `embed: false` is deliberate: the host app already embeds
      the framework under its own `Frameworks/`, and iOS resolves
      a single copy at load time via the bundle search path.
      Embedding it twice would double the IPA's framework payload
      and risk a code-sign mismatch in a future signed build.
  - Added `FRAMEWORK_SEARCH_PATHS: $(inherited)
    $(PROJECT_DIR)/Frameworks` to the extension (same value as
    the host app) so the linker finds the framework.
  - Added `OTHER_LDFLAGS: $(inherited) -lresolv` to the extension
    (mirrors the host app's flag from
    `docs/ai/GOMOBILE_BINDINGS.md` §4 / `libresolv`). The BSD
    resolver symbols come from the Go runtime, not from anything
    app-vs-extension specific, so any target linking
    OlcRTCMobile needs the flag.
  - Kept `APPLICATION_EXTENSION_API_ONLY = YES`, kept code signing
    disabled, kept entitlements detached.
- New `ios/OlcRTCClient/Sources/PacketTunnelProvider/GomobileExtensionProbe.swift`:
  - Gated on `#if canImport(OlcRTCMobile)` so scaffold-only builds
    that don't have the framework keep compiling.
  - Defines a single internal enum `GomobileExtensionProbe` with a
    `static func touch() -> Bool` that calls only the
    configure/read-only symbols `MobileSetDebug(false)` and
    `MobileIsRunning()`. The Bool return + `@discardableResult`
    keeps the function body intact under whole-module
    optimization, so the linker actually pulls in OlcRTCMobile.
  - **Never called from `startTunnel`**. The principal class
    `PacketTunnelProvider.startTunnel(options:completionHandler:)`
    is unchanged and still surfaces `notWiredYet`.
  - File header documents what this probe is and what it is NOT
    in detail, so a future reader can't misread the link edge as
    a runtime hookup.
- New `.github/workflows/packet-tunnel-gomobile-probe.yml`
  (workflow name: `Packet Tunnel Gomobile Probe`):
  - Triggers on push to the `packet-tunnel-gomobile-probe`
    branch (paths-scoped to relevant inputs) and on
    `workflow_dispatch`.
  - Steps: checkout w/ submodules, `setup-go` against the upstream
    `go.mod`, `brew install xcodegen`, run
    `scripts/build-gomobile-ios.sh`, `xcodegen generate`,
    `xcodebuild -list`, then **one** unsigned Release
    `iphoneos` build of the host scheme.
  - Building the host scheme exercises the extension's compile +
    link path because the host scheme already depends on
    `PacketTunnelProvider: all` (see
    `ios/OlcRTCClient/project.yml`). We deliberately do NOT add a
    standalone extension scheme — Xcode does not let you build an
    app-extension scheme on its own without a host, so a separate
    scheme would add complexity without probe value.
  - Post-build `Confirm extension binary actually linked` step
    asserts
    `build/DerivedData/Build/Products/Release-iphoneos/PacketTunnelProvider.appex/PacketTunnelProvider`
    exists, then prints `file` / `otool -L` / a `nm -u | grep -c
    Mobile` count of OlcRTCMobile-prefixed undefined symbol refs
    in the extension binary. Diagnostic only — the source-of-truth
    pass/fail is `xcodebuild build`.
  - `Probe summary` step writes the result, commit SHA, and what
    the probe does and does NOT prove to `$GITHUB_STEP_SUMMARY`,
    with `if: always()` so a red run also produces the summary.
  - **Not** in this workflow on purpose: IPA packaging, IPA
    structure validation, host-app tests, simulator builds.
    Single-purpose so a failure points at one thing.
- Documentation:
  - `docs/ROADMAP.md` — Milestone 3 status flipped from
    `not started` to `in progress`; the first three tasks (link
    edge in `project.yml`, `libresolv` flag, probe file, probe
    workflow) marked `[x]`; blockers split into "build/link probe
    is NOT blocked, runs from CI today" vs "runtime tasks still
    blocked on Milestone 2".
  - `docs/ai/GOMOBILE_BINDINGS.md` §4 (libresolv) — note that the
    flag is now applied to **both** targets. New
    "Extension-target linking (probe in progress)" subsection
    enumerates the five expected failure modes (extension-unsafe
    APIs, undefined symbols, Xcode refusing dynamic frameworks,
    `APPLICATION_EXTENSION_API_ONLY` violations, unsigned-extension
    embedding issues) so a red run is easy to triage.
  - This `TASK_LOG.md` entry.
- Expected acceptance criterion: `Packet Tunnel Gomobile Probe`
  workflow runs green on this branch. Green means the extension
  compiled and linked against OlcRTCMobile under
  `APPLICATION_EXTENSION_API_ONLY = YES`. **Green does NOT mean**
  VPN Mode runtime works — the extension still does not start any
  tunnel.
- **Not done in this step**, intentionally: real VPN packet
  routing, any `MobileStart*` call from the extension, any signing
  or entitlement attachment, any Go-core change, any new feature,
  any change to the host-app `iOS App + Gomobile Build` workflow
  or to the unsigned IPA artifact.

---

### 2026-05-28 — Document MVP release checklist and roadmap

- Goal: capture what the current green state actually guarantees,
  what is deliberately deferred, and what the next sequenced
  technical chunks are, so the project is easy to continue from a
  cold pickup. Documentation only — no app behavior change, no Go
  core change, no signing, no new CI workflow.
- New `docs/RELEASE_CHECKLIST.md`: the source of truth for what
  "release-ready" means today (Local Proxy MVP, unsigned IPA, VPN
  Mode stubbed). Sections: current artifact (workflow / artifact /
  unsigned-IPA caveat); CI checks (one row per workflow step,
  what it verifies); manual QA checklist (deferred until a signing
  identity exists — every item from the task brief: launch after
  signing, About caveats, invalid-profile Start gating, valid URI
  import, invalid URI import, subscription import with mixed
  valid/invalid lines, save/select/delete profile, real
  Local Proxy Start/Stop/Check/Ping, log privacy spot check, VPN
  Mode stub clarity); security/privacy checklist (no keyHex /
  password / raw `olcrtc://` in logs, no secrets in CI logs,
  unsigned IPA not distributed as production); known limitations
  (unsigned IPA not installable, PacketTunnelProvider stubbed,
  Local Proxy not background-reliable, no signing workflow, no
  real-device QA, no App Store / TestFlight path); sign-off
  protocol.
- New `docs/ROADMAP.md`: five sequenced milestones with goal /
  tasks / blockers / acceptance criteria for each:
  1. **Local Proxy MVP** — mostly complete today; lists the
     remaining intra-milestone follow-ups (App Group profile
     storage, Keychain-for-key ADR, deferred real-device QA).
  2. **Real-device signed build** — paid Apple Developer account,
     App IDs for both targets, provisioning + NE entitlement,
     separate `signed-build` workflow, re-attached
     `.entitlements`, manual sideload + walk the QA checklist.
  3. **PacketTunnelProvider / gomobile feasibility probe** — link
     `OlcRTCMobile.xcframework` into the extension under
     `APPLICATION_EXTENSION_API_ONLY = YES`, audit headers, smoke
     test memory budget, mirror sanitized logs into App Group.
  4. **Background-safe VPN runtime** — real
     `NETunnelProviderManager` install + `NEPacketTunnelNetworkSettings`
     + Go runtime bridging `NEPacketTunnelFlow`, on-demand rules
     decision, observe `NEVPNStatusDidChange`.
  5. **Distribution strategy** — explicit ADR (App Store /
     TestFlight / enterprise / ad-hoc), corresponding CI pipeline,
     App Store privacy nutrition label.
- GitHub issue templates rewritten for the standalone-iOS context.
  Replaced the upstream-inherited templates (which told iOS users
  to file mobile bugs elsewhere and which were Russian-language)
  with four iOS-specific templates: `bug_report.yml`,
  `ci_failure.yml`, `feature_request.yml`, `security.yml`. Each
  template enforces the project's privacy rules in pre-flight
  checkboxes (no real keyHex, no real `olcrtc://`, no real
  subscription URL with credentials). `config.yml` now points at
  the upstream Go core, at `docs/ai/`, and at
  `docs/{RELEASE_CHECKLIST,ROADMAP}.md` instead of the unrelated
  upstream chat. Removed the inherited `question.yml` (it
  conflicted with the iOS-only scope and routed users at the wrong
  audience).
- Root `README.md`: added explicit links to
  `docs/RELEASE_CHECKLIST.md` and `docs/ROADMAP.md` from the
  "Read me before touching anything" list (items 5 and 6); the
  layout block mentions `.github/ISSUE_TEMPLATE/` and `docs/`;
  the Distribution-status paragraph cross-links to both new docs;
  the latest green workflow + artifact name are already in the
  Status block.
- Recommended next technical branch (record so the next session
  can pick this up cold): **`packet-tunnel-gomobile-probe`** —
  Milestone 3 from `docs/ROADMAP.md`. Rationale: Milestone 2
  (signing) is blocked on resources outside our control (paid
  Apple Developer account + real device), while Milestone 3 can
  start as a **build-only feasibility experiment** today without a
  signing identity. The smallest first cut: add
  `OlcRTCMobile.xcframework` as a framework dependency on the
  `PacketTunnelProvider` target in `project.yml` (`embed: false,
  codeSign: false` to avoid double-embedding the Go runtime), let
  `iOS App + Gomobile Build` discover whether the link succeeds
  under `APPLICATION_EXTENSION_API_ONLY = YES`, and capture the
  outcome in `docs/ai/GOMOBILE_BINDINGS.md`. If it fails, isolate
  the offending symbol behind a shim. The runtime side (real
  `startTunnel` wiring, packet flow bridging) stays gated on
  Milestone 2 — but knowing whether the link is even possible is
  a Milestone-3 prerequisite we can answer from CI alone.
  - Alternative: **`signed-build-prep`** (Milestone 2 plumbing)
    — write the parameterized `signed-build` workflow against
    GitHub Actions encrypted secrets in dry-run mode, with the
    actual identity loaded later. Less learning per token spent
    than the probe; prefer only if the team has a paid account
    already lined up.
- **Not done in this step**, intentionally: any app behavior
  change; any Swift / Go / project.yml edit; any signing; any
  feature; any new CI workflow; any change to the IPA packaging
  layout. Documentation and issue templates only.

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
