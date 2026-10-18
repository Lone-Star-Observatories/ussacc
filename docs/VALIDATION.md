# Build validation — 2026-10-17

Validated on an Apple silicon Mac using Swift 6.4 / macOS SDK 27.

- Native SwiftUI app compiled and packaged as `build/USS ACC.app`.
- 8 Swift Testing tests passed in 2 suites: operational importance invariants, exact sender matching, reserved/invalid scores, persistence, inbox baseline/replay protection and reviewed calendar journey imports.
- Apple Intelligence runtime check: known sender asking for meeting confirmation → OP5; routine delayed-parcel notice → OP1. These are fictional test inputs, not incoming mail.
- Embedded interactive terminal executed a harmless marker command through its PTY successfully and removed the marker.
- The app rendered six demo screens for visual review with no account connections.
- Ad-hoc app signature verified using `codesign --verify --deep --strict`.
- Info.plist and packaging script passed syntax checks.

## Local toolchain workaround

The machine's Command Line Tools installation has stale private SwiftPM interfaces, lacks the platform macro plugin search path, and does not automatically find Xcode's test support libraries. Validation used an ignored, isolated copy of the public SwiftPM interfaces, explicit Xcode platform plugin/test library paths and the native SwiftPM build engine. No installed toolchain files were changed. The app's ordinary build instructions and CI use full Xcode, which supplies those libraries normally.

## Checks requiring real accounts

Apple Mail automation consent, provider-specific Trash behavior, Calendar consent, and push-notification delivery were not exercised against personal accounts. They are opt-in. Messages and calling are explicitly system handoffs; no live incoming message/call adapter is claimed. Calendar candidates and manual itinerary legs do not verify tickets or live transport status.

Developer runtime checks (after packaging):

```sh
'build/USS ACC.app/Contents/MacOS/USSACC' --check-classifier
'build/USS ACC.app/Contents/MacOS/USSACC' --check-terminal
'build/USS ACC.app/Contents/MacOS/USSACC' --snapshot-dir /tmp/ussacc-previews
```

The classifier check needs an available Apple Intelligence model. These flags use fictional data and never apply filter rules to an account.
