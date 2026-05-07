# Quickstart: good-recording

**Feature**: 001-good-recording
**Date**: 2026-05-07
**Audience**: Developers contributing to the v1 implementation. End-user
documentation will be authored separately at release time.

This is the operational handbook for getting from "fresh git clone" to
"a Universal Binary `.app` you can drag into `/Applications`" in under
10 minutes on Apple Silicon, plus the verify steps that map directly to
the spec's success criteria.

---

## 0. Prerequisites

| Tool          | Version                  | Why                                       |
|---------------|--------------------------|-------------------------------------------|
| macOS         | 15.0 (Sequoia) or later  | Matches min deployment target.            |
| Xcode         | 16.0 or later            | Swift 6 toolchain.                        |
| Command Line Tools | bundled with Xcode  | `xcrun notarytool`, `lipo`.               |
| `swift`       | 6.0+                     | Default with Xcode 16; verify `swift --version`. |
| Apple ID      | Developer Program member | Only needed for signing & notarization.   |
| Git           | any recent version       | —                                         |

A test macOS VM with **Screen Recording, Microphone, Notifications**
permissions pre-granted is recommended for running the integration test
suite (see §5). The `scripts/ci/setup-vm-snapshot.sh` script documents
how to bake one.

---

## 1. Clone & open

```bash
git clone <repo-url>
cd home-spec/apps/good-recording
open GoodRecording.xcodeproj
```

The Xcode project is pre-configured with:

- 1 app target: `GoodRecording`
- 3 test targets: `UnitTests`, `IntegrationTests`, `UITests`
- 5 local SPM packages under `Sources/Features/US{N}-...`
- 7 local SPM packages under `Sources/Core/{Capture,Encoding,Storage,Permissions,Hotkey,Notifications,Logging}`

Each Features module declares only the Core modules it actually depends on
— enforced by an `XCDependencyLint` Run Phase script that fails the build
if a Feature accidentally pulls in another Feature.

---

## 2. Run the app locally

In Xcode:

- Scheme: `GoodRecording (Debug)`
- Run destination: `My Mac` (Apple Silicon native or Rosetta — both work)
- ⌘R

On first run, macOS will prompt for Screen Recording permission the first
time you click "开始录制". This is expected — accept and run again. The
permission request flow itself is part of US1 AC3 and is exercised by
`PermissionsContractTests`.

### Disabling individual user-story features

`Sources/App/FeatureFlags.swift` exposes compile-time flags:

```swift
enum FeatureFlags {
    static let US1_RECORDING       = true       // P1 MVP — must stay true
    static let US2_SCOPE_SELECTION = true       // toggle to reduce surface
    static let US3_AUDIO_SOURCES   = true
    static let US4_QUALITY_SETTINGS = true
    static let US5_AUDIO_ONLY_MODE = true
}
```

Setting any to `false` removes the corresponding UI surface entirely (the
SPM module's source files compile out via `#if`). Use this to ship an
MVP build that proves US1 in isolation (Constitution III).

---

## 3. Build a release Universal Binary

```bash
cd home-spec
./scripts/build-universal.sh
```

What the script does:

1. `xcodebuild archive -scheme GoodRecording -archivePath build/GoodRecording.xcarchive -destination "generic/platform=macOS" ARCHS="arm64 x86_64"`
2. `xcodebuild -exportArchive -archivePath build/GoodRecording.xcarchive -exportPath build/Release -exportOptionsPlist scripts/ExportOptions.plist`
3. `lipo -info build/Release/GoodRecording.app/Contents/MacOS/GoodRecording` (verifies both architectures)

Output: `build/Release/GoodRecording.app`.

### Sign and notarize

```bash
./scripts/sign-and-notarize.sh build/Release/GoodRecording.app
```

Reads `DEVELOPER_ID_APPLICATION` and `NOTARYTOOL_PROFILE` from your
keychain (configured once via `xcrun notarytool store-credentials`).

Output: a notarized + stapled `.app` and a `.dmg` next to it.

---

## 4. Run unit tests

```bash
xcodebuild test -scheme GoodRecording -destination "platform=macOS,arch=arm64" -only-testing:UnitTests
```

Expectations:

- 100% of tests in `UnitTests` MUST pass on every PR.
- Coverage for `Sources/Core/*` MUST be ≥ 80% (CI lint).
- Tests in `UnitTests` MUST NOT touch `ScreenCaptureKit`,
  `AVCaptureSession`, or any TCC-gated API. Use protocol abstractions +
  fakes (the Capture module provides `CaptureSourceMock`).

---

## 5. Run integration & UI tests (TCC-gated)

These suites require a macOS VM snapshot with Screen Recording,
Microphone, and Notifications pre-granted.

```bash
./scripts/ci/run-tcc-tests.sh
```

What the script does:

1. Boots the `gr-tcc-base` Tart VM from a known-good snapshot.
2. Copies the built `.app` and the test bundles into the VM.
3. Runs:
   - `xcodebuild test -only-testing:IntegrationTests` (Capture pipeline E2E)
   - `xcodebuild test -only-testing:UITests` (XCUITest smoke + Accessibility Inspector)
4. Pulls back JUnit XML + screenshots into `build/test-results/`.

Per Constitution III, every user story must have at least one
acceptance test exercising its Independent Test from `spec.md`:

| US | Test class                                    | Asserts                                                                 |
|----|-----------------------------------------------|--------------------------------------------------------------------------|
| US1| `RecordingFlowTests.testOneClickRecordSave`   | full-screen 10 s recording → file plays in QuickTime / size > 0          |
| US2| `ScopeSelectionTests.testWindowOnlyCapture`   | recorded frame contains only target window pixels                        |
| US3| `AudioSourcesTests.testSystemAudioOnly`       | output audio contains test-tone, not ambient noise                       |
| US4| `QualitySettingsTests.test720pMovPersists`    | output is 720p mov; setting survives app restart                          |
| US5| `AudioOnlyModeTests.testM4aPlayback`          | output is m4a, plays in QuickTime, contains audio                        |

---

## 6. Verify Constitution & SC compliance

| Constitution gate           | Verify command                                                                    |
|-----------------------------|------------------------------------------------------------------------------------|
| I — local-first             | `./scripts/ci/check-no-network.sh` (instruments `nettop` while running smoke test)|
| II — simplicity             | `./scripts/ci/check-strings.sh` (greps Localizable for forbidden tech words)      |
| III — independent stories   | `xcodebuild test -only-testing:UnitTests/FeatureModulesIsolationTests`            |
| IV — macOS native           | `./scripts/ci/check-entitlements.sh` + `lipo -info <binary>` + `spctl --assess`   |
| V — observability           | `./scripts/ci/check-logs-contract.sh` (runs scripted session, validates schema)   |
| Platform constraints        | `./scripts/ci/perf-bench.sh` (cold start, idle/peak RSS, interaction latency)     |

| Success criterion (spec.md) | Verify in            |
|-----------------------------|-----------------------|
| SC-001 (90 s first record)  | UI test + manual      |
| SC-002 (≤ 3 steps)          | UI test (step counter) |
| SC-003 (≤ 3 s stop→Finder)  | Integration test       |
| SC-004 (30 min playable)    | Integration test (long-haul)|
| SC-005 (80% non-engineer)   | Manual usability round |
| SC-006 (zero network)       | `check-no-network.sh`  |
| SC-007 (100% playable on userStop) | Integration test (×100 loop) |
| SC-008 (cold start ≤ 2 s)   | `perf-bench.sh`        |
| SC-009 (RSS ≤ 200 / 500 MB) | `perf-bench.sh`        |
| SC-010 (interaction ≤ 100 ms)| `perf-bench.sh`       |

CI fails on any verify step regression.

---

## 7. Common dev workflows

### Add a new event to local logs

1. Add the event row to `contracts/logs.md` event catalog.
2. Add a `case` to `Logger.Event` enum in `Sources/Core/Logging/`.
3. Add a `LogContractTests` assertion that the event is emitted by the
   feature exercising it.
4. Run `xcodebuild test -only-testing:UnitTests/LogContractTests`.

### Add a new entitlement

1. Justify in a Complexity Tracking entry in `plan.md` (mandatory if not
   already in `contracts/permissions.md`).
2. Add to `apps/good-recording/Resources/GoodRecording.entitlements`.
3. Update `contracts/permissions.md` matrix.
4. Update CI lint allow-list in `scripts/ci/check-entitlements.sh`.
5. Constitution review (per Constitution IV) before merge.

### Bump min macOS version

1. Update `MACOSX_DEPLOYMENT_TARGET` in `apps/good-recording/Sources/App/`
   target build settings.
2. Update `spec.md` Assumptions §最低支持系统.
3. Update `plan.md` Technical Context.
4. Update `quickstart.md` §0 Prerequisites.
5. If the bump removes a previously-supported version → MAJOR constitution
   bump (per Constitution governance §版本策略).

---

## 8. Where to look when something breaks

| Symptom                                         | First place to look                                            |
|-------------------------------------------------|----------------------------------------------------------------|
| App won't open after build                      | `xcrun spctl -a -vv build/Release/GoodRecording.app` (signing)  |
| Recording starts but file is 0 bytes            | Local logs (`Settings → 数据与日志 → 查看日志`) → look for `recording_failed` |
| Can't get past "需要您的允许" card              | System Settings → Privacy & Security → Screen Recording        |
| Hotkey doesn't work                             | Logs → `hotkey_register_failed`; check for app conflict        |
| Universal Binary missing one arch               | `lipo -info` on the binary; check `ARCHS` in build settings    |

---

## 9. Definition of Done (per user story)

A user story is considered complete when:

- [ ] All Acceptance Scenarios in `spec.md` pass as automated tests.
- [ ] Every relevant FR is covered by ≥ 1 test.
- [ ] `LogContractTests` covers every new event.
- [ ] `check-entitlements.sh` and `check-no-network.sh` still pass.
- [ ] Manual VoiceOver smoke pass on the new surface.
- [ ] Documentation: relevant contract files updated; this `quickstart.md`
      updated if a new dev workflow appeared.
- [ ] Logs reviewed for sensitive data leakage.
