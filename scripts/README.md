# scripts/

Build helpers for the iOS client. **Currently empty** — the gomobile
build script (`ios-bind.sh` or equivalent) lands in the next step of
the task log.

Expected future contents:

- `ios-bind.sh` — `gomobile bind -target=ios ./mobile` against
  `third_party/olcrtc/mobile`, producing
  `ios/OlcRTCClient/Frameworks/OlcRTCMobile.xcframework`.
- Anything else CI needs that does not belong in the workflow file.
