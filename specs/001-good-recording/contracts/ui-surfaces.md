# Contract: UI Surfaces

**Feature**: 001-good-recording
**Date**: 2026-05-07

This contract enumerates every user-visible surface in v1, the states
each surface can be in, and the legal transitions between them. It is
the source of truth for UI snapshot tests, accessibility tests, and
the XCUITest smoke suite.

---

## S1. Main Window (`MainWindow`)

The single window users interact with for almost everything in v1.

### States

| State              | Visible elements                                                         | Allowed actions                                                |
|--------------------|---------------------------------------------------------------------------|----------------------------------------------------------------|
| `idle`             | Mode segmented control (录屏 / 仅录音), Range picker, Audio toggles, **「开始录制」** primary button, Settings & About menu items | Change config; click 开始录制 → `preparing` |
| `preparing`        | Spinner overlay; permission prompts may appear                            | Cancel (back to `idle`)                                        |
| `recording`        | Live timer, **「停止录制」** primary button (red), elapsed time label     | Click 停止 → `finalizing`; switch app freely                   |
| `finalizing`       | Brief progress (≤ 1 s typical)                                            | None (locked)                                                  |
| `saved`            | "已保存" banner inside window + system notification + "在 Finder 中显示" button | Click banner / button → opens Finder; Auto-fade after 5 s → `idle` |
| `errorPermission`  | Inline error card with 三要素 (what / why / next: "打开系统设置")         | "打开系统设置"; "稍后" → `idle`                                |
| `errorRuntime`     | Inline error card (e.g. magnetic disk full warning, encoder failure)      | "在 Finder 中显示" partial file (if any); "知道了" → `idle`     |

### Legal transitions

```text
idle ──开始──▶ preparing ──ready──▶ recording ──停止/global hotkey──▶ finalizing ──ok──▶ saved ──auto/click──▶ idle
                  │                                                  │
            permission denied                                    failure
                  ▼                                                  ▼
            errorPermission ──返回──▶ idle                        errorRuntime ──返回──▶ idle
```

### Accessibility requirements

- `开始录制 / 停止录制` button MUST have `accessibilityLabel` matching
  the Chinese label and an English fallback when locale is `en`.
- Timer in `recording` state MUST be VoiceOver-announced as
  "已录制 X 分 Y 秒" at most once per 30 s (avoid spam).
- All inline error cards MUST be reachable in a single VoiceOver swipe
  group; the "next-step" action MUST be the default keyboard focus.

---

## S2. Range Picker (`RangePicker` — segmented control + sub-UI)

Inline inside `MainWindow.idle`. Three segments:

| Segment         | Sub-UI                                                              | Default                              |
|-----------------|---------------------------------------------------------------------|--------------------------------------|
| 整个屏幕         | Display chooser dropdown (only visible when ≥ 2 displays connected) | Main display                         |
| 单个窗口         | "选择窗口…" button → opens `WindowPickerOverlay` (S5)               | None until user picks                |
| 自定义区域       | "选择区域…" button → opens `RegionPickerOverlay` (S6)               | Last-selected rect (after 1st time)  |

### Behavioral contracts

- Switching segments MUST NOT lose the previously-selected sub-value
  (so user can A/B between full-screen and window mid-config without
  re-picking the window).
- If the previously selected window is no longer present when user
  re-enters that segment, UI MUST gracefully prompt to pick again.

---

## S3. Audio Toggles (`AudioToggleStrip`)

Inline inside `MainWindow.idle`. Two independent toggle switches with
labels:

| Toggle      | Off → On effect                                                                  |
|-------------|----------------------------------------------------------------------------------|
| 环境音       | If mic permission missing → S7 errorPermission; else: enabled                    |
| 系统声音     | If system audio permission missing → S7 errorPermission; else: enabled           |

In `audioOnly` mode, the strip is the **only** record-path config UI shown
(range picker is hidden).

If both toggles are off in `audioOnly` mode, the 开始录制 button MUST be
disabled with a tooltip "请至少选择一个音源" (FR-018).

---

## S4. Menu Bar Status Item (`MenuBarStatusItem`)

A minimal `NSStatusItem` that appears **only while recording** (i.e. when
`MainWindow` is in `recording`/`finalizing`).

### Visible content

- Recording icon (small red dot) + elapsed time `MM:SS` (toggleable via
  Settings.showMenuBarTimer).

### Menu (click)

- "停止录制" (primary action)
- "显示主窗口"
- 分隔
- "保存到: …" (read-only, shows current target dir)

### Accessibility

- VoiceOver label of the status item MUST be "good-recording 录制中
  X 分 Y 秒".

---

## S5. Window Picker Overlay (`WindowPickerOverlay`)

A modal `NSPanel` (or SCContentSharingPicker fallback) that lists
currently visible windows, each row showing app icon + window title.

### Behavior

- Search field at top; filters incrementally as user types.
- Single-click selects + dismisses (returns selection to `RangePicker`).
- Esc dismisses without changing selection.
- Empty state: "没有可录制的窗口" + "重新扫描" button.

---

## S6. Region Picker Overlay (`RegionPickerOverlay`)

A full-screen transparent overlay (`NSPanel` w/ `nonactivatingPanel`
+ `borderless` style) per active display.

### Behavior

- Mouse drag draws a rectangle with handles; release confirms.
- Live size readout `(W × H)` at the cursor.
- Esc cancels; Enter confirms (or auto-confirms on release after
  500 ms delay to prevent accidental confirms).
- Last rectangle persisted in `Settings`; "重置区域" item in S2
  clears it.

---

## S7. Permission Card (inline / errorPermission state)

Triggered when the user attempts to start recording without a required
permission (Screen Recording, Microphone, System Audio).

### Card structure (FR-008 / FR-010)

```text
┌────────────────────────────────────────────────────────┐
│ [Icon]  我们需要您的允许才能 [描述功能]                │
│                                                        │
│ macOS 出于隐私保护，需要您在系统设置中手动授予权限。   │
│ 我们不会将任何数据发送到设备之外。                     │
│                                                        │
│ [打开系统设置]                       [稍后再说]        │
└────────────────────────────────────────────────────────┘
```

Each text line is required; the "we won't send anything off-device"
sentence is mandatory across **all three** permission cards (Screen,
Mic, Notifications).

---

## S8. Settings Window (`SettingsWindow`)

Modal `NSWindow`, single tab in v1 (multi-tab structure ready for v2+).

### Sections

1. **保存位置** — Default save dir; per-mode override; "选择…" button
   → `NSOpenPanel`.
2. **录制质量** — Resolution dropdown (720p / 1080p / 1440p / 原生);
   container (mp4 / mov); codec (when container = mov).
3. **菜单栏** — Toggle for "录制时在菜单栏显示计时器".
4. **快捷键** — Read-only display of current hotkey `⌃⇧K` + helper text
   "v1 暂不支持自定义"。
5. **数据与日志** — "查看日志" / "导出日志" / "清空日志" buttons; data
   export note ("您的录制文件、设置、日志均存储在本地。").
6. **恢复默认设置** — Destructive button (red text); requires confirm
   alert per FR-016.

---

## S9. About Window (`AboutWindow`)

Standard `NSAboutPanel` plus an additional "隐私" section explaining
local-first commitment (FR-026), data locations, and the network-egress
guarantee.

---

## S10. System Notifications

| Trigger                                  | Title          | Body example                               | Actions                |
|------------------------------------------|----------------|--------------------------------------------|------------------------|
| Recording finalized (any reason)         | "已保存"        | `Recording 2026-05-07 20.12.33.mp4`        | "在 Finder 中显示"      |
| Disk space < 500 MB during recording     | "已自动停止"    | "磁盘空间不足，已保存当前录制。"            | "在 Finder 中显示"      |
| Target window/display gone               | "已自动停止"    | "录制目标已消失，已保存当前录制。"          | "在 Finder 中显示"      |
| Global hotkey registration failed        | "全局快捷键不可用" | "请使用菜单栏或主窗口的停止按钮。"        | (none)                 |

If notification permission is denied, an in-app banner inside
`MainWindow` replaces the system notification (graceful degradation).

---

## Global hotkey contract (`⌃⇧K`)

- Lifecycle: registered when `MainWindow` enters `recording`; unregistered
  when leaving (`finalizing` → no longer needed).
- Effect when pressed: equivalent to clicking the primary "停止录制"
  button. Idempotent if pressed twice rapidly.
- Failure mode: if registration fails (e.g. another app holds it), the
  S10 "全局快捷键不可用" notification fires once at recording start;
  recording proceeds normally.

---

## Localization contract (v1)

- Languages: zh-Hans (primary), en (fallback). Auto-switch by system
  locale.
- All user-facing strings (including SOSS — `Localizable.xcstrings`)
  MUST have both translations before release. CI step verifies no
  missing keys.
