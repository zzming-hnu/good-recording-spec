# Contract: Permissions

**Feature**: 001-good-recording
**Date**: 2026-05-07

This contract enumerates every permission the v1 app requests, where it
asks, what `NSUsageDescription` text it ships, and how denials are
handled. It is the source of truth for `Info.plist`, the entitlement
file, and the permission-flow XCUITests.

The minimum set was justified in `research.md` R6.

---

## Permission matrix

| Permission                       | Mechanism            | Triggered when…                                   | Denial behavior                                      | spec FR refs        |
|----------------------------------|----------------------|---------------------------------------------------|------------------------------------------------------|---------------------|
| Screen Recording                 | TCC (system)         | First click of 开始录制 in `.video` mode          | UI shows S7 Permission Card → 打开系统设置 deeplink | FR-001, FR-008, US1 AC3 |
| Microphone (audio-input)         | TCC + entitlement    | First time 环境音 toggle is turned ON, OR start of audio-only recording with ambient enabled | S7 Permission Card; toggle reverts                  | FR-009, FR-010, US3 AC2 |
| System Audio (via SCK)           | Bundled with Screen Recording on macOS 15 | Same as Screen Recording                          | Same as Screen Recording                            | FR-009, FR-011      |
| Notifications                    | UserNotifications    | First successful recording finalize, **only if** user has notifications enabled in Settings | Silent fallback to in-app banner; never re-prompt   | FR-020, S10 fallback note |
| User-selected file access        | Sandbox + bookmark   | User picks custom save dir in Settings            | If bookmark resolution fails later → fall back to default + one-time notice | FR-021              |

No permission is requested at app launch. All requests are **just-in-time**
and tied to a clear user action — directly aligned with constitution II
(普通用户简洁体验) and the "no surprise dialogs" expectation.

---

## `NSUsageDescription` strings (Info.plist)

All strings follow the spec's "三要素" rule (what / why / what we won't
do) and use the "I" voice (the user's perspective).

| Key                                           | Value (zh-Hans)                                                                                                       |
|-----------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| `NSScreenCaptureUsageDescription`             | "good-recording 需要录制您的屏幕画面与系统声音以完成录屏功能。所有数据仅保存在您本地，绝不发送到设备之外。"           |
| `NSMicrophoneUsageDescription`                | "good-recording 需要使用麦克风以录入您的环境音。仅在您主动开始录制时录入；所有录音数据仅保存在您本地，绝不发送到设备之外。" |
| `NSAppleEventsUsageDescription`               | (留空 — v1 不使用)                                                                                                    |

English fallback (`Localizable.xcstrings`) follows the same template,
translated.

These strings appear in the macOS system dialog. They MUST be reviewed
against the Apple App Review guideline 5.1.1 even though v1 doesn't ship
to the App Store — wording quality is a Constitution II requirement.

---

## Entitlements file (`GoodRecording.entitlements`)

The complete v1 entitlement set:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>                          <true/>

  <!-- Audio capture -->
  <key>com.apple.security.device.audio-input</key>                   <true/>

  <!-- Default save directories -->
  <key>com.apple.security.assets.movies.read-write</key>             <true/>
  <key>com.apple.security.assets.music.read-write</key>              <true/>

  <!-- User-selected save directories -->
  <key>com.apple.security.files.user-selected.read-write</key>       <true/>
  <key>com.apple.security.files.bookmarks.app-scope</key>            <true/>
</dict>
</plist>
```

### Forbidden entitlements (will fail CI)

- `com.apple.security.network.client` / `network.server` — would violate
  constitution I. CI MUST fail if these appear in the entitlement file.
- `com.apple.security.cs.disable-library-validation` /
  `cs.allow-unsigned-executable-memory` — anti-Sandbox; would violate
  constitution IV.
- `com.apple.security.temporary-exception.*` — exceptions are a code
  smell; if a future case requires one, plan-level escalation required
  (Complexity Tracking entry mandatory).

A CI lint job `scripts/ci/check-entitlements.sh` enumerates the
entitlement file and fails the build on any forbidden key.

---

## Permission flow diagrams

### Flow A — First screen recording (US1 AC3)

```text
User: clicks 开始录制
  ↓
App: checks SCShareableContent permission
  ↓
  ├── granted → start recording
  └── denied  → S7 Permission Card
                ↓
                User clicks 打开系统设置
                ↓
                App opens `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`
                ↓
                User toggles permission ON in System Settings
                ↓
                User returns to app, clicks 开始录制 again → granted path
```

App MUST detect the granted state without requiring a restart (use
`SCShareableContent.current` re-fetch on window focus).

### Flow B — First mic toggle (US3 AC2)

```text
User: turns 环境音 toggle ON
  ↓
App: AVCaptureDevice.requestAccess(for: .audio)
  ↓
  ├── granted → toggle stays ON
  └── denied  → toggle reverts to OFF + S7 Permission Card
```

### Flow C — Notifications (FR-020 + S10 fallback)

```text
First recording finalize:
  ↓
  if Settings.notificationsEnabled is true AND
     UNUserNotificationCenter.authorizationStatus == .notDetermined:
       request authorization (.alert + .sound)
  ↓
  granted → fire system notification
  denied  → fire in-app banner inside MainWindow (no further reprompt)
```

The app MUST NOT re-request notification permission once denied. A
"开启通知" link in Settings → 数据与日志 deeplinks to System Settings
for users who change their mind.

---

## Audit & verification

- The entitlement lint script (`scripts/ci/check-entitlements.sh`)
  enforces the forbidden list above.
- An integration test `PermissionsContractTests` MUST verify that:
  - Each `NSUsageDescription` key is present in the built `Info.plist`.
  - String length ≥ 50 chars (catches accidental "TODO").
  - Each string contains the substring "本地" or "device" (zh-Hans /
    en respectively) — guarding the privacy promise.
- Manual review checklist in release process: "Did any new feature
  require an entitlement? If yes, was constitution I re-checked?"
