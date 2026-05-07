---

description: "Task list for 001-good-recording (macOS 屏幕与音频录制工具) v1"
---

# Tasks: good-recording (macOS 屏幕与音频录制工具)

**Input**: Design documents from `/specs/001-good-recording/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Tests are **INCLUDED** for this feature. Constitution III
declares TDD mandatory for NON-NEGOTIABLE principles, and US1 / US3 sit
on top of those principles. Each user story therefore lists test tasks
that MUST be written and FAIL before the implementation tasks in the
same phase begin.

**Organization**: Tasks are grouped by user story. Within a story:
tests first → models → services → UI → cross-wiring. Each story is
independently completable; the only hard ordering is Setup → Foundational
→ each user story phase.

## Format: `[ID] [P?] [Story] Description (file path)`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks).
- **[Story]**: Which user story this task belongs to (e.g., `US1`, `US2`).
- Setup / Foundational / Polish phases have NO story label.
- Every task includes the exact file path it touches.

## Path Conventions

- App target: `apps/good-recording/`
- Sources: `apps/good-recording/Sources/{App,Features,Core}/`
- Tests: `apps/good-recording/Tests/{UnitTests,IntegrationTests,UITests}/`
- Resources: `apps/good-recording/Resources/`
- Repo-wide scripts: `scripts/` (build, signing, CI lint)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the empty macOS app shell — Xcode project, build
settings, entitlements, scripts. After this phase the project compiles
and produces an empty `.app` bundle that passes Sandbox + signing.

- [ ] T001 Create monorepo skeleton: `apps/good-recording/`, `scripts/`, `scripts/ci/` directories at repo root
- [ ] T002 Initialize Xcode project at `apps/good-recording/GoodRecording.xcodeproj` with one app target (`GoodRecording`) and three test targets (`UnitTests`, `IntegrationTests`, `UITests`)
- [ ] T003 Configure project build settings: `MACOSX_DEPLOYMENT_TARGET = 15.0`, `SWIFT_VERSION = 6.0`, `ARCHS = arm64 x86_64`, `ENABLE_HARDENED_RUNTIME = YES`, `ENABLE_APP_SANDBOX = YES` in `apps/good-recording/GoodRecording.xcodeproj/project.pbxproj`
- [ ] T004 Create `apps/good-recording/Resources/GoodRecording.entitlements` with the exact 6 entitlement keys listed in `contracts/permissions.md` (sandbox + audio-input + movies/music + user-selected files + bookmarks)
- [ ] T005 [P] Populate `apps/good-recording/Resources/Info.plist` with bundle id `com.zzming.good-recording`, `LSApplicationCategoryType = public.app-category.video`, and the three `NSUsageDescription` strings exactly as in `contracts/permissions.md`
- [ ] T006 [P] Create `apps/good-recording/Resources/Localizable.xcstrings` with `zh-Hans` (primary) and `en` (fallback) locales; seed with empty key list (per-feature tasks add keys)
- [ ] T007 [P] Create `apps/good-recording/Resources/Assets.xcassets` with placeholder app icon and accent color
- [ ] T008 [P] Create `scripts/build-universal.sh` (xcodebuild archive → exportArchive → lipo verify) per `quickstart.md` §3
- [ ] T009 [P] Create `scripts/sign-and-notarize.sh` (codesign → notarytool submit → stapler) per `quickstart.md` §3
- [ ] T010 [P] Create CI lint scripts under `scripts/ci/`: `check-entitlements.sh` (forbidden key list per `contracts/permissions.md`), `check-no-network.sh` (nettop assertion per Constitution I / SC-006), `check-strings.sh` (forbidden tech words in Localizable per Constitution II), `check-logs-contract.sh` (validates JSON Lines schema per `contracts/logs.md`)
- [ ] T011 [P] Create `apps/good-recording/Sources/App/FeatureFlags.swift` with the 5 boolean flags `US1_RECORDING ... US5_AUDIO_ONLY_MODE` per `quickstart.md` §2
- [ ] T012 [P] Create `scripts/ci/xc-dependency-lint.sh` Run Phase script that fails the build if any `Sources/Features/US{N}-*` module imports any other Feature module (enforces independent-test boundary per Constitution III)

**Checkpoint**: `xcodebuild -scheme GoodRecording build` succeeds; `./scripts/ci/check-entitlements.sh` passes; `lipo -info` reports both arm64 + x86_64.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the seven `Core/*` modules and the shared data types
every user story will depend on. **No user story work can begin until
this phase is complete.**

⚠️ **CRITICAL**: Phase 2 must be 100% green before starting any US phase.

### Shared types (data-model.md)

- [ ] T013 Define foundational enums and structs in `apps/good-recording/Sources/Core/Capture/Types.swift`: `RecordingMode`, `RecordingTarget`, `WindowSnapshot`, `AudioSourceSet`, `EndReason`, `TargetTemplate` (per data-model.md V1–V7)
- [ ] T014 Define encoding types in `apps/good-recording/Sources/Core/Encoding/EncodingTypes.swift`: `VideoConfig`, `VideoResolution`, `VideoCodec`, `ContainerFormat` with `(.mp4, .hevc)` validation (data-model.md V4–V5)
- [ ] T015 Define entity models in `apps/good-recording/Sources/Core/Storage/Models.swift`: `Recording`, `RecordingPreset`, `Settings` with all fields per data-model.md E1–E3 (Codable, with explicit `String` rawValue for enums)

### Core modules (parallel-safe — different directories)

- [ ] T016 [P] Implement `apps/good-recording/Sources/Core/Logging/Logger.swift`: JSON Lines writer with day-boundary rotation (≤ 30 days / ≤ 100 MB), OSLog mirror, `Logger.Event` enum covering every event in `contracts/logs.md`, log directory at sandbox `Library/Logs/GoodRecording/`
- [ ] T017 [P] Implement `apps/good-recording/Sources/Core/Permissions/Permissions.swift`: TCC helpers for Screen Recording (`SCShareableContent.current`), Microphone (`AVCaptureDevice.requestAccess(for: .audio)`), Notifications (`UNUserNotificationCenter`); each helper exposes `current`, `request`, and an `openSettings()` deeplink per the URLs in `contracts/permissions.md`
- [ ] T018 [P] Implement `apps/good-recording/Sources/Core/Storage/SettingsStore.swift`: `UserDefaults`-backed `Settings` persistence, security-scoped bookmark resolution + storage for user-selected save dirs, fallback to `~/Movies/Good Recording/` on bookmark failure (per `contracts/output-files.md`)
- [ ] T019 [P] Implement `apps/good-recording/Sources/Core/Storage/RecordingFileNamer.swift`: produces `Recording {YYYY-MM-DD} {HH.MM.SS}.{ext}` filenames with collision-handling ` (N)` suffix per `contracts/output-files.md`
- [ ] T020 [P] Implement `apps/good-recording/Sources/Core/Notifications/Notifier.swift`: `UserNotifications` wrapper for the 4 notification types in `contracts/ui-surfaces.md` S10, with in-app banner fallback delegate when notification permission is denied
- [ ] T021 [P] Implement `apps/good-recording/Sources/Core/Hotkey/GlobalHotkey.swift`: Carbon `RegisterEventHotKey` wrapper for `⌃⇧K`; exposes `register(onTrigger:)` returning `success | conflict`, `unregister()`; emits `hotkey_register_*` log events (per `contracts/logs.md`)

### Capture & encoding pipelines (sequential — depend on T013–T015)

- [ ] T022 Implement `apps/good-recording/Sources/Core/Capture/CaptureCoordinator.swift` (`actor`): owns `SCStream` lifecycle, exposes `start(target:audio:config:) async` / `stop() async`, emits sample buffers via `AsyncSequence`, maps SCK errors → `EndReason`
- [ ] T023 Implement `apps/good-recording/Sources/Core/Capture/MicrophoneCapture.swift`: `AVCaptureSession` + `AVCaptureAudioDataOutput`, hot-unplug detection (`AVAudioSession.routeChangeNotification`)
- [ ] T024 Implement `apps/good-recording/Sources/Core/Encoding/AssetWriterPipeline.swift`: `AVAssetWriter` setup for mp4 / mov / m4a per resolution/codec params in `contracts/output-files.md`; metadata items injection (title / creator / creationDate / description JSON); temp file in `tmp/recording-{id}.{ext}.partial` then atomic move on finalize
- [ ] T025 Implement `apps/good-recording/Sources/Core/Encoding/AudioMixer.swift`: mixes mic + system audio sample buffers into a single AAC track (per data-model.md V3 + research.md R2)

### Test infrastructure

- [ ] T026 [P] Create test mocks `apps/good-recording/Tests/UnitTests/_Mocks/CaptureSourceMock.swift`, `AssetWriterMock.swift` so unit tests can exercise capture/encode logic without TCC (per `quickstart.md` §4)
- [ ] T027 [P] Create `apps/good-recording/Tests/IntegrationTests/_Helpers/TCCSnapshotSetup.swift`: integration test bootstrap that asserts the test runner is in a TCC-pre-authorized environment (skips with clear message otherwise) per `quickstart.md` §5

### App shell

- [ ] T028 Implement `apps/good-recording/Sources/App/App.swift` (`@main` SwiftUI App), `AppDelegate.swift` (status item lifecycle), `ContentView.swift` (root view that mounts `MainWindow`)
- [ ] T029 Implement `apps/good-recording/Sources/App/MainWindow.swift`: SwiftUI `WindowGroup` shell containing the placeholder for `idle` state from `contracts/ui-surfaces.md` S1 (filled in by US1 phase)

**Checkpoint**: All Core/* modules build with ≥ 80% unit-test coverage; CaptureCoordinator can be exercised via mock; app launches to an empty MainWindow without crashing. **User stories can now begin in parallel.**

---

## Phase 3: User Story 1 — 一键录屏与一键保存 (Priority: P1) 🎯 MVP

**Goal**: User opens app, clicks one button, records full screen, clicks again to stop, finds a playable file in `~/Movies/Good Recording/`. Global hotkey `⌃⇧K` and menu-bar status item also trigger stop.

**Independent Test**: 全新安装 → 第一次启动并按提示授予屏幕录制权限 → 点击主按钮 → 等待 10 秒 → 再点主按钮 → 在 `~/Movies/Good Recording/` 下能找到一个可在 QuickTime Player 与 Finder 预览中正常播放的视频文件。

### Tests for User Story 1 (write FIRST, ensure they FAIL before implementation) ⚠️

- [ ] T030 [P] [US1] Unit test for filename collision handling in `apps/good-recording/Tests/UnitTests/CoreStorage/RecordingFileNamerTests.swift`
- [ ] T031 [P] [US1] Unit test for `CaptureCoordinator` start/stop state transitions (using `CaptureSourceMock`) in `apps/good-recording/Tests/UnitTests/CoreCapture/CaptureCoordinatorTests.swift`
- [ ] T032 [P] [US1] Unit test for `RecordingViewModel` state machine (`idle → preparing → recording → finalizing → saved`) in `apps/good-recording/Tests/UnitTests/FeaturesUS1/RecordingViewModelTests.swift`
- [ ] T033 [P] [US1] Unit test for `GlobalHotkey` wrapper success/conflict callbacks in `apps/good-recording/Tests/UnitTests/CoreHotkey/GlobalHotkeyTests.swift`
- [ ] T034 [P] [US1] Integration test `RecordingFlowTests.testOneClickRecordSave` (spec US1 Independent Test) in `apps/good-recording/Tests/IntegrationTests/US1/RecordingFlowTests.swift` — records 10 s full-screen, asserts file exists, decodes via `AVURLAsset`, duration ≥ 9.5 s
- [ ] T035 [P] [US1] Integration test `RecordingFlowTests.testStopViaHotkey` — start recording programmatically, post `⌃⇧K` event, asserts file saved within 3 s
- [ ] T036 [P] [US1] UI test `MainWindowUITests.testHappyPathRecordSave` in `apps/good-recording/Tests/UITests/US1/MainWindowUITests.swift` — clicks 开始 → waits → clicks 停止 → asserts "已保存" banner appears
- [ ] T037 [P] [US1] UI test `PermissionsUITests.testScreenRecordingDenied` (spec US1 AC3) — denies permission in TCC mock, clicks 开始, asserts S7 Permission Card with "打开系统设置" button is shown

### Implementation for User Story 1

- [ ] T038 [US1] Implement `apps/good-recording/Sources/Features/US1-Recording/RecordingViewModel.swift`: state machine driving MainWindow states (`idle → preparing → recording → finalizing → saved`), uses `CaptureCoordinator` + `AssetWriterPipeline` + `SettingsStore`
- [ ] T039 [US1] Implement `apps/good-recording/Sources/Features/US1-Recording/MainWindowContent.swift`: SwiftUI view binding to `RecordingViewModel`, single primary button that toggles 开始/停止; injects into `App/MainWindow.swift` shell from T029
- [ ] T040 [US1] Implement `apps/good-recording/Sources/Features/US1-Recording/SavedBannerView.swift`: in-window "已保存" banner with "在 Finder 中显示" action (auto-fade after 5 s per `contracts/ui-surfaces.md` S1)
- [ ] T041 [US1] Implement "Show in Finder" via `NSWorkspace.activateFileViewerSelecting(_:)` in `apps/good-recording/Sources/Features/US1-Recording/SavedBannerView.swift` — same file
- [ ] T042 [US1] Implement `apps/good-recording/Sources/Features/US1-Recording/PermissionCardView.swift`: S7 card per `contracts/ui-surfaces.md` with three-element copy + "打开系统设置" deeplink
- [ ] T043 [US1] Wire `GlobalHotkey` from `Core/Hotkey` into `RecordingViewModel`: register on `recording` entry, unregister on `finalizing`; on conflict, fire S10 "全局快捷键不可用" notification (FR-029)
- [ ] T044 [US1] Implement `apps/good-recording/Sources/Features/US1-Recording/MenuBarStatusItem.swift`: `NSStatusItem` shown only while recording, with timer label + 停止 / 显示主窗口 menu items (S4); reads `Settings.showMenuBarTimer`
- [ ] T045 [US1] Wire `Notifier.recordingSaved(fileURL:)` to fire after successful finalize (S10 row 1)
- [ ] T046 [US1] Wire log events `recording_requested`, `recording_started`, `recording_stopped`, `recording_failed`, `hotkey_*` from US1 code paths per `contracts/logs.md`
- [ ] T047 [US1] Add zh-Hans + en strings for US1 UI to `Resources/Localizable.xcstrings` (button labels, banner text, permission card copy, menu items)

**Checkpoint**: ✅ **MVP complete** — User Story 1 fully functional. Ship-ready slice that exercises the entire pipeline (Capture → Encode → Save → Notify) with default settings (full-screen, 1080p, mp4, ambient mic on). All US1 tests green.

---

## Phase 4: User Story 2 — 选择录制范围 (Priority: P2)

**Goal**: User can pick what to record before starting — full screen of a chosen display, a specific window, or a custom rectangle.

**Independent Test**: 在 US1 完成的基础上，可以单独打开"录制范围"切换到"窗口"并选中一个 Safari 窗口 → 录制 → 停止 → 输出文件中只包含被选中的 Safari 窗口内容。

### Tests for User Story 2 (write FIRST) ⚠️

- [ ] T048 [P] [US2] Unit test for `RangePickerViewModel` state preservation across segment switches in `apps/good-recording/Tests/UnitTests/FeaturesUS2/RangePickerViewModelTests.swift`
- [ ] T049 [P] [US2] Unit test for `WindowPickerViewModel` filter / search in `apps/good-recording/Tests/UnitTests/FeaturesUS2/WindowPickerViewModelTests.swift`
- [ ] T050 [P] [US2] Integration test `ScopeSelectionTests.testWindowOnlyCapture` (spec US2 Independent Test) in `apps/good-recording/Tests/IntegrationTests/US2/ScopeSelectionTests.swift` — records a launched test-fixture window, asserts captured frame's pixel histogram matches the fixture's signature color (not background)
- [ ] T051 [P] [US2] Integration test `ScopeSelectionTests.testRegionRectPersisted` (spec US2 AC2) — pick rect, record, restart, asserts last rect is the default
- [ ] T052 [P] [US2] Integration test `ScopeSelectionTests.testTargetWindowDisappears` (spec US2 AC3) — start recording a fixture window, programmatically close the window, asserts recording auto-stops within 1 s and file is saved with `EndReason.targetGone`
- [ ] T053 [P] [US2] Integration test `ScopeSelectionTests.testMultiDisplayRequiresChoice` (spec US2 AC4) — simulates 2 displays, asserts UI requires display selection before start
- [ ] T054 [P] [US2] UI test `RangePickerUITests.testSegmentSwitching` — switch full-screen → window → region → window again, asserts previously-picked window selection survives

### Implementation for User Story 2

- [ ] T055 [P] [US2] Implement `apps/good-recording/Sources/Features/US2-ScopeSelection/RangePicker.swift`: SwiftUI segmented control (整个屏幕 / 单个窗口 / 自定义区域) per `contracts/ui-surfaces.md` S2
- [ ] T056 [P] [US2] Implement `apps/good-recording/Sources/Features/US2-ScopeSelection/DisplayChooser.swift`: dropdown shown only when `NSScreen.screens.count >= 2`
- [ ] T057 [US2] Integrate `SCContentSharingPicker` (macOS 15) in `apps/good-recording/Sources/Features/US2-ScopeSelection/SystemContentPicker.swift` as the primary window/region picker per research.md R4
- [ ] T058 [US2] Implement self-built fallback `apps/good-recording/Sources/Features/US2-ScopeSelection/WindowPickerOverlay.swift`: `NSPanel` window list with app icon + title + search field per S5
- [ ] T059 [US2] Implement self-built `apps/good-recording/Sources/Features/US2-ScopeSelection/RegionPickerOverlay.swift`: full-screen transparent `NSPanel` per display, drag-rectangle with handles + size readout per S6, persists last rect to `Settings`
- [ ] T060 [US2] Wire selected target into `RecordingViewModel` (extends T038): map UI selection → `RecordingTarget` enum cases
- [ ] T061 [US2] Persist last-window-snapshot and last-region-rect in `Settings._lastUsed` preset via `SettingsStore` (extends T018)
- [ ] T062 [US2] Detect target window/display gone during recording: subscribe to `NSWorkspace` window-close + `NSApplication.didChangeScreenParametersNotification`; trigger `CaptureCoordinator.stop(reason: .targetGone)` and emit `target_window_lost` log event
- [ ] T063 [US2] Add zh-Hans + en strings for US2 UI to `Resources/Localizable.xcstrings`

**Checkpoint**: User Story 2 functional. US1 still works. User can pick what to record. All US2 tests green.

---

## Phase 5: User Story 3 — 音频源选择 (Priority: P2)

**Goal**: Each recording's audio sources (环境音 / 系统音 / both / neither) are independently togglable.

**Independent Test**: 在 US1 基础上单独打开音频面板 → 勾选"系统声音"并取消"环境音" → 在浏览器播放一段视频 → 录制 5 秒 → 停止 → 输出文件中包含该视频的声音但听不到环境噪声。

### Tests for User Story 3 (write FIRST) ⚠️

- [ ] T064 [P] [US3] Unit test for `AudioMixer` two-source mixing & sample-rate matching in `apps/good-recording/Tests/UnitTests/CoreEncoding/AudioMixerTests.swift`
- [ ] T065 [P] [US3] Unit test for `AudioToggleViewModel` blocking start when audio-only-mode + no source selected in `apps/good-recording/Tests/UnitTests/FeaturesUS3/AudioToggleViewModelTests.swift`
- [ ] T066 [P] [US3] Integration test `AudioSourcesTests.testSystemAudioOnly` (spec US3 Independent Test) in `apps/good-recording/Tests/IntegrationTests/US3/AudioSourcesTests.swift` — plays a known test-tone via `AVAudioPlayer`, records 5 s with system-audio-only, asserts FFT of audio track has tone peak at expected frequency
- [ ] T067 [P] [US3] Integration test `AudioSourcesTests.testMixedMicAndSystem` (spec US3 AC1) — asserts both sources audible in single AAC track without echo
- [ ] T068 [P] [US3] Integration test `AudioSourcesTests.testMicPermissionDenied` (spec US3 AC2) — asserts S7 card shown, recording does not start, toggle reverts
- [ ] T069 [P] [US3] Integration test `AudioSourcesTests.testAudioDeviceUnplug` (spec US3 AC3) — start recording with mic, simulate device removal mid-recording, asserts recording continues + warning notification fires + log entry
- [ ] T070 [P] [US3] Integration test `AudioSourcesTests.testSilentVideo` (spec US3 AC4) — both audio toggles off, asserts output file has legal silent audio track playable in QuickTime
- [ ] T071 [P] [US3] Integration test `AudioSourcesTests.test30MinPlayable` (spec SC-004) — 30-min mixed recording, asserts QuickTime full playback completes with both tracks intact

### Implementation for User Story 3

- [ ] T072 [P] [US3] Implement `apps/good-recording/Sources/Features/US3-AudioSources/AudioToggleStrip.swift`: two SwiftUI `Toggle` controls bound to `AudioSourceSet` per `contracts/ui-surfaces.md` S3
- [ ] T073 [US3] Wire mic permission request flow when 环境音 toggle turns ON (extends T017): on denial, revert toggle + show S7 card
- [ ] T074 [US3] Wire system-audio + mic toggles into `RecordingViewModel.preset.audioSources` (extends T038)
- [ ] T075 [US3] Connect `MicrophoneCapture` (T023) → `AudioMixer` (T025) → `AssetWriterPipeline` audio input pipeline; gate mic stream on `audioSources.ambient`, gate SCK audio on `audioSources.system`
- [ ] T076 [US3] Handle `AVAudioSession.routeChangeNotification` mid-recording: keep recording running with remaining sources, fire S10-style notification, emit `audio_device_changed` log event
- [ ] T077 [US3] Update `RecordingViewModel.canStart` to respect audio-only + zero-audio rule (FR-018 — but actual audio-only mode comes in US5; this guard prepares the validator)
- [ ] T078 [US3] Wire log events `audio_device_changed`, `audio_mix_overflow` per `contracts/logs.md`
- [ ] T079 [US3] Add zh-Hans + en strings for US3 UI to `Resources/Localizable.xcstrings`

**Checkpoint**: User Story 3 functional. US1 + US2 still work. Audio source mix is per-recording configurable. All US3 tests green.

---

## Phase 6: User Story 4 — 录制质量与格式设置 (Priority: P3)

**Goal**: Settings window with resolution / container / codec choices that persist across launches; "恢复默认" with confirmation.

**Independent Test**: 进入设置 → 把分辨率改为 720p、格式改为 mov → 录制 5 秒 → 输出文件实际短边为 720 像素且容器为 .mov；重启应用后设置仍保持 720p / mov。

### Tests for User Story 4 (write FIRST) ⚠️

- [ ] T080 [P] [US4] Unit test for `SettingsViewModel` resolution / container / codec validation (rejects `.mp4 + .hevc`) in `apps/good-recording/Tests/UnitTests/FeaturesUS4/SettingsViewModelTests.swift`
- [ ] T081 [P] [US4] Unit test for `SettingsStore.restoreDefaults` requires confirmation flag in `apps/good-recording/Tests/UnitTests/CoreStorage/SettingsStoreRestoreDefaultsTests.swift`
- [ ] T082 [P] [US4] Integration test `QualitySettingsTests.test720pMovPersists` (spec US4 Independent Test) in `apps/good-recording/Tests/IntegrationTests/US4/QualitySettingsTests.swift` — sets 720p + mov, records 5 s, asserts file probe reports `(short_side == 720, container == "mov")`; relaunches app via `XCUIApplication`, asserts settings still 720p + mov
- [ ] T083 [P] [US4] Integration test `QualitySettingsTests.testUnsupportedFormatFallback` (spec US4 AC2) — set codec to one made unavailable in test (mock VT failure), assert fallback to default and one-time notice
- [ ] T084 [P] [US4] UI test `SettingsWindowUITests.testRestoreDefaultsRequiresConfirm` (spec US4 AC4 + FR-016) — click 恢复默认, asserts NSAlert appears, cancel leaves settings unchanged, confirm resets

### Implementation for User Story 4

- [ ] T085 [P] [US4] Implement `apps/good-recording/Sources/Features/US4-QualitySettings/SettingsWindow.swift`: `NSWindow` with sections per `contracts/ui-surfaces.md` S8 (保存位置 / 录制质量 / 菜单栏 / 快捷键 / 数据与日志 / 恢复默认)
- [ ] T086 [P] [US4] Implement `apps/good-recording/Sources/Features/US4-QualitySettings/SettingsViewModel.swift`: bindings to `Settings` fields with validation (reject `.mp4 + .hevc`)
- [ ] T087 [P] [US4] Implement `apps/good-recording/Sources/Features/US4-QualitySettings/QualitySection.swift`: resolution dropdown (720p / 1080p / 1440p / 原生), container (mp4 / mov), codec (visible only when container = mov)
- [ ] T088 [P] [US4] Implement `apps/good-recording/Sources/Features/US4-QualitySettings/SaveLocationSection.swift`: directory picker via `NSOpenPanel` + security-scoped bookmark persistence (uses `SettingsStore`)
- [ ] T089 [US4] Wire `RecordingViewModel` to read resolution / container / codec from `SettingsStore._lastUsed.videoConfig` at start (extends T038)
- [ ] T090 [US4] Implement "恢复默认" with `NSAlert` confirmation in `apps/good-recording/Sources/Features/US4-QualitySettings/RestoreDefaultsSection.swift`
- [ ] T091 [US4] Implement quality fallback logic in `AssetWriterPipeline` (extends T024): on unsupported codec → fall back to `(.mp4, .h264, .res1080p)` + emit `settings_changed` log + one-time `Notifier` notice
- [ ] T092 [US4] Wire log events `settings_changed`, `settings_reset` per `contracts/logs.md`
- [ ] T093 [US4] Add zh-Hans + en strings for US4 settings UI to `Resources/Localizable.xcstrings`

**Checkpoint**: User Story 4 functional. US1 + US2 + US3 still work. Quality config persistent. All US4 tests green.

---

## Phase 7: User Story 5 — 仅音频录制 (Priority: P3)

**Goal**: A "仅录音" mode that produces an m4a audio-only file using the same audio source choices.

**Independent Test**: 切换到"仅录音" → 选择"环境音" → 录 5 秒 → 输出一个独立可播放的音频文件（不含视频轨）且大小显著小于同时长视频文件。

### Tests for User Story 5 (write FIRST) ⚠️

- [ ] T094 [P] [US5] Unit test for `ModeViewModel` switching toggles audio-only flag and hides range picker in `apps/good-recording/Tests/UnitTests/FeaturesUS5/ModeViewModelTests.swift`
- [ ] T095 [P] [US5] Integration test `AudioOnlyModeTests.testM4aPlayback` (spec US5 Independent Test) in `apps/good-recording/Tests/IntegrationTests/US5/AudioOnlyModeTests.swift` — switch to audio-only, record 5 s with mic, asserts file extension is `.m4a`, plays in QuickTime, has 1 audio track + 0 video tracks, file size < 1 MB
- [ ] T096 [P] [US5] Integration test `AudioOnlyModeTests.testNoSourceBlocked` (spec US5 AC3) — audio-only mode + both toggles off, click 开始, asserts UI is blocked + tooltip shows "请至少选择一个音源"
- [ ] T097 [P] [US5] Integration test `AudioOnlyModeTests.testSkipsScreenPermission` (spec US5 AC1) — audio-only mode, asserts no Screen Recording TCC prompt is triggered when starting

### Implementation for User Story 5

- [ ] T098 [P] [US5] Implement `apps/good-recording/Sources/Features/US5-AudioOnlyMode/ModeSegmentedControl.swift`: top-level segmented control (录屏 / 仅录音) at the top of MainWindow content
- [ ] T099 [US5] Wire mode toggle into `RecordingViewModel` to set `RecordingMode` (extends T038); when `.audioOnly`, hide `RangePicker` (US2) and switch container to `.m4a`
- [ ] T100 [US5] Implement audio-only capture path in `apps/good-recording/Sources/Features/US5-AudioOnlyMode/AudioOnlyCaptureCoordinator.swift`: composes `MicrophoneCapture` + (optional) SCK system-audio-only stream (no video) directly into `AssetWriterPipeline` configured for m4a
- [ ] T101 [US5] Block 开始 button when audio-only + `AudioSourceSet.any == false` (FR-018); add tooltip per S3 contract
- [ ] T102 [US5] Update `Permissions` flow: when audio-only mode, do not pre-request Screen Recording (extends T017) — request only mic if 环境音 enabled
- [ ] T103 [US5] Add zh-Hans + en strings for US5 mode UI to `Resources/Localizable.xcstrings`

**Checkpoint**: All 5 user stories functional and independently testable. v1 feature surface complete.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, accessibility, performance, scripts, docs.

- [ ] T104 [P] Implement `apps/good-recording/Sources/Features/US1-Recording/AboutWindow.swift` (S9) with privacy section explaining local-first commitment + entitlement transparency
- [ ] T105 [P] Implement Settings → 数据与日志 actions in `apps/good-recording/Sources/Features/US4-QualitySettings/DataAndLogsSection.swift`: 查看日志 (`NSWorkspace.open(logsDirURL)`), 导出日志 (`NSSavePanel` → zip), 清空日志 (twice-confirmed delete)
- [ ] T106 [P] Edge case: disk space monitoring at `apps/good-recording/Sources/Core/Storage/DiskSpaceWatcher.swift` — polls free space every 5 s during recording, triggers `CaptureCoordinator.stop(reason: .diskFull)` when < 500 MB + S10 notification (FR-023, edge case)
- [ ] T107 [P] Edge case: orphan `.partial` file cleanup at app launch in `apps/good-recording/Sources/App/AppDelegate.swift` — sweeps sandbox `tmp/` for `recording-*.partial`, deletes them silently (matches Clarification #3 + spec edge case)
- [ ] T108 [P] Edge case: super-long recording auto-segment in `apps/good-recording/Sources/Core/Encoding/AssetWriterPipeline.swift` (extends T024) — when expected mp4 size approaches 4 GB, finalize current writer and start a new segment file, append ` part2`, ` part3`, ... suffix
- [ ] T109 [P] Edge case: rapid 开始/停止 click debounce in `apps/good-recording/Sources/Features/US1-Recording/RecordingViewModel.swift` (extends T038) — primary button disabled during transition states; integration test `RecordingFlowTests.testRapidClicks` in `apps/good-recording/Tests/IntegrationTests/US1/RecordingFlowTests.swift` verifies no race / no orphan files
- [ ] T110 [P] Accessibility: VoiceOver labels + keyboard shortcuts on every interactive control across US1–US5 views; Accessibility Inspector script `scripts/ci/check-a11y.sh` enumerates all controls and asserts non-empty labels
- [ ] T111 [P] Performance: instrument cold-start (XCTMetric) in `apps/good-recording/Tests/IntegrationTests/Perf/PerfBenchmarks.swift` asserting cold start ≤ 2.0 s on Apple Silicon (SC-008); idle RSS ≤ 200 MB; recording RSS peak ≤ 500 MB (SC-009); interaction p95 ≤ 100 ms (SC-010)
- [ ] T112 [P] CI: `scripts/ci/run-tcc-tests.sh` orchestrates Tart VM snapshot + xcodebuild test for IntegrationTests + UITests per `quickstart.md` §5
- [ ] T113 [P] CI: `scripts/ci/perf-bench.sh` runs `PerfBenchmarks` and fails build on regression beyond 10 % vs. baseline
- [ ] T114 [P] CI: `scripts/ci/check-no-network.sh` final implementation — runs scripted recording session, asserts `nettop` reports zero out-of-bundle TCP/UDP traffic from GoodRecording PID (SC-006)
- [ ] T115 [P] CI: `scripts/ci/check-strings.sh` final implementation — greps `Localizable.xcstrings` for forbidden tech words `JSON|YAML|endpoint|hash|payload|stack trace`; fails on hit (Constitution II)
- [ ] T116 [P] Run full quickstart.md §6 verification matrix end-to-end on Apple Silicon + Intel-via-Rosetta CI jobs; tag `v1.0.0-rc1` if all green
- [ ] T117 [P] Author repo-root `README.md` with project overview, install instructions (drag-to-Applications), system requirements (macOS 15+), privacy promise summary, link to `specs/001-good-recording/`
- [ ] T118 [P] Update `.specify/memory/constitution.md` Sync Impact Report to mark `TODO(MIN_MACOS_VERSION)` as `(closed in plan.md / spec clarification 2026-05-07 → macOS 15.0)`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)** — no deps; T005–T012 are mutually parallel.
- **Phase 2 (Foundational)** — depends on Phase 1; T013 → T014 → T015 sequential (types build on each other); T016–T021 parallel (different Core dirs); T022–T025 sequential (capture/encoding pipeline) and depend on T013–T015; T026–T027 parallel; T028–T029 last.
- **Phase 3 (US1 — MVP)** — depends on Phase 2 complete. Tests (T030–T037) parallel. Implementation: T038 → T039 → (T040, T041, T042 parallel) → T043 → T044 → T045 → T046 → T047.
- **Phase 4 (US2)** — depends on Phase 2 + ideally Phase 3 (US1 main button drives the start that selects the target). Within Phase 4: tests (T048–T054) parallel; implementation T055 + T056 parallel → T057 → T058 + T059 parallel → T060 → T061 → T062 → T063.
- **Phase 5 (US3)** — depends on Phase 2 (specifically T023 + T025) + ideally Phase 3. Independent of US2. Tests (T064–T071) parallel.
- **Phase 6 (US4)** — depends on Phase 2 + ideally Phase 3 (the settings drive what US1's recording uses). Tests (T080–T084) parallel; implementation T085–T088 parallel → T089–T093 sequential.
- **Phase 7 (US5)** — depends on Phase 2 + ideally Phase 3 + Phase 5 (audio sources used by US5). Tests (T094–T097) parallel.
- **Phase 8 (Polish)** — depends on all desired user stories complete; all tasks marked [P] except where they touch already-shared files.

### User Story Dependencies (logical, not strictly enforced)

- **US1 (P1, MVP)**: depends only on Foundational. **Independently shippable.**
- **US2 (P2)**: depends on Foundational; cleanly composable with US1's main button.
- **US3 (P2)**: depends on Foundational; independent of US2.
- **US4 (P3)**: depends on Foundational; reads settings used by US1; independent of US2 / US3 surfaces but extends US1's recording with quality knobs.
- **US5 (P3)**: depends on Foundational + US3 (reuses audio sources / mixer); does NOT depend on US2 (no range picker in audio-only mode).

### Within Each User Story (TDD discipline)

1. Tests (marked `⚠️`) MUST be written and MUST FAIL before implementation tasks in the same phase begin.
2. Models / view models before services / coordinators.
3. Coordinators / services before view bindings.
4. Story complete (all its acceptance scenarios pass) before moving to next priority.
5. **Commit at every checkpoint**, especially after each user story's checkpoint, to keep `git bisect` precise (Constitution III ↔ progressive delivery).

### Parallel Opportunities

- All Setup tasks marked `[P]` (T005–T012) can run together.
- All Foundational `[P]` tasks (T016–T021, T026–T027) run together.
- Once Foundational is done, US1 / US2 / US3 / US4 / US5 can all start in parallel if you have multiple developers (subject to the soft dependencies in the previous section).
- Inside each user story, all `⚠️` test tasks marked `[P]` can be drafted in parallel (different test files).
- Polish phase: every `[P]` task is independent.

---

## Parallel Example: User Story 1 Test Drafting

```bash
# Launch all US1 tests for drafting in parallel (TDD red phase):
Task: "Unit test for filename collision handling in apps/good-recording/Tests/UnitTests/CoreStorage/RecordingFileNamerTests.swift"
Task: "Unit test for CaptureCoordinator state transitions in apps/good-recording/Tests/UnitTests/CoreCapture/CaptureCoordinatorTests.swift"
Task: "Unit test for RecordingViewModel state machine in apps/good-recording/Tests/UnitTests/FeaturesUS1/RecordingViewModelTests.swift"
Task: "Unit test for GlobalHotkey wrapper in apps/good-recording/Tests/UnitTests/CoreHotkey/GlobalHotkeyTests.swift"
Task: "Integration test testOneClickRecordSave in apps/good-recording/Tests/IntegrationTests/US1/RecordingFlowTests.swift"
Task: "Integration test testStopViaHotkey in apps/good-recording/Tests/IntegrationTests/US1/RecordingFlowTests.swift"
Task: "UI test testHappyPathRecordSave in apps/good-recording/Tests/UITests/US1/MainWindowUITests.swift"
Task: "UI test testScreenRecordingDenied in apps/good-recording/Tests/UITests/US1/PermissionsUITests.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 only) 🎯

1. Complete **Phase 1: Setup** (T001–T012).
2. Complete **Phase 2: Foundational** (T013–T029) — **this is the longest phase but unlocks every story**.
3. Complete **Phase 3: User Story 1** (T030–T047).
4. **STOP and validate**: run the US1 Independent Test from `spec.md` end-to-end on a real Mac.
5. If green: **ship-ready MVP**. Cut a `v0.1.0` tag, get user feedback, decide what to do next based on real usage.

### Incremental Delivery (recommended)

1. Setup + Foundational → "alpha skeleton" (no UI yet).
2. + US1 → MVP / `v0.1.0` (one-button screen recorder with default settings).
3. + US2 → `v0.2.0` (添加范围选择).
4. + US3 → `v0.3.0` (音频源选择).
5. + US4 → `v0.4.0` (设置面板).
6. + US5 → `v0.5.0` (仅录音模式).
7. + Polish (Phase 8) → `v1.0.0` (full feature, performance / a11y / CI / docs).

Each version is a complete, independently testable, ship-quality slice — direct embodiment of Constitution III.

### Parallel Team Strategy (with multiple developers)

- All hands on Setup + Foundational together (T001–T029).
- After Foundational checkpoint:
  - Dev A: US1 (Phase 3) — owns the MVP path
  - Dev B: US2 (Phase 4)
  - Dev C: US3 (Phase 5)
  - When Dev B / C unblock, Dev A pivots to US4 (Phase 6) and US5 (Phase 7).
- Polish (Phase 8) is parallel by design — assign tasks by area of expertise (a11y, perf, scripts, docs).

---

## Notes

- `[P]` = different files, no dependencies on incomplete tasks.
- `[Story]` label maps task to user story for traceability and feature-flag scoping.
- Each user story is independently completable and testable (Constitution III hard constraint).
- Verify tests fail before implementing (Constitution III TDD requirement).
- Commit after each task or each checkpoint (Constitution III + Spec Kit auto-commit hooks).
- Avoid: vague tasks, same-file conflicts within a `[P]` group, cross-story imports (CI lint will fail per T012).
- File path collisions during parallel work: re-check `Localizable.xcstrings` and `MainWindow.swift` adds — these are the natural collision points; coordinate via PR-level merge order.
