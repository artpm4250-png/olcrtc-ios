# olcrtc-ios

Native iOS client for [olcRTC](https://github.com/openlibrecommunity/olcrtc).

**Status:** scaffold only. The SwiftUI app, the `NetworkExtension`
`PacketTunnelProvider` target, and the CI scaffold-build workflow are
in place. The Go core (`gomobile bind` → `OlcRTCMobile.xcframework`)
is **not** yet integrated — see [`docs/ai/TASK_LOG.md`](docs/ai/TASK_LOG.md)
for the next step.

This is a **standalone** repository, separate from the Go core upstream.
The upstream is consumed as a git submodule under `third_party/olcrtc`.

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
.github/workflows/               — CI (scaffold build today)
scripts/                         — build helpers (gomobile bind etc., placeholder)
third_party/olcrtc/              — git submodule: openlibrecommunity/olcrtc @ fix/all
```

## Cloning

```sh
git clone --recurse-submodules https://github.com/artpm4250-png/olcrtc-ios.git
# or, after a plain clone:
git submodule update --init --recursive
```

## CI

`.github/workflows/ios-scaffold.yml` runs on `macos-latest` and
validates that the XcodeGen spec generates, the app compiles for
both `iphonesimulator` and `iphoneos` unsigned, and the unit tests
pass. It does **not** build the Go core. Trigger via
`workflow_dispatch` or by pushing changes to `ios/OlcRTCClient/**`,
`docs/ai/**`, or the workflow file itself.

## Distribution status

CI today produces no `.ipa`. When the Go core is integrated, the
follow-up `ios-build.yml` workflow will produce an **unsigned** `.ipa`
artifact, suitable only for inspection / later signing. The unsigned
build will **not** install and run as a VPN on a stock iPhone — that
requires Apple signing + provisioning + the `NetworkExtension`
entitlement (none configured here).
