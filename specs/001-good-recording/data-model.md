# Phase 1 Data Model: good-recording

**Feature**: 001-good-recording
**Date**: 2026-05-07
**Source**: [spec.md](./spec.md) §Key Entities + [research.md](./research.md)

This document captures the persisted and in-memory data shapes the v1
feature relies on. It is an **interface-level** description (Swift type
sketches with field names, types, validation rules, and state transitions),
not a code drop. The actual `struct` / `enum` definitions land in
`apps/good-recording/Sources/Core/` during implementation.

Persistence locations are normative; field types follow Swift 6 conventions.

---

## E1. `Recording`

A single completed (or in-progress) capture session and its on-disk artifact.

| Field            | Type                                         | Notes / Validation |
|------------------|----------------------------------------------|--------------------|
| `id`             | `UUID`                                       | Generated at start; immutable. |
| `mode`           | `RecordingMode` (enum, see V1)               | `.video` or `.audioOnly`. |
| `startedAt`      | `Date`                                       | UTC timestamp at start. |
| `endedAt`        | `Date?`                                      | `nil` while recording. Set on stop / abort. |
| `duration`       | `TimeInterval` (computed)                    | `endedAt - startedAt`; ≥ 0. |
| `target`         | `RecordingTarget?` (enum, see V2)            | `nil` only for `.audioOnly`. |
| `audioSources`   | `AudioSourceSet` (struct, see V3)            | `{ ambient: Bool, system: Bool }`. |
| `videoConfig`    | `VideoConfig?` (struct, see V4)              | `nil` only for `.audioOnly`. |
| `containerFormat`| `ContainerFormat` (enum, see V5)             | `.mp4 | .mov | .m4a`. Must match `mode`. |
| `fileURL`        | `URL`                                        | Final on-disk location. Must exist on stop. |
| `fileSizeBytes`  | `Int64`                                      | Filled in after writer.finishWriting(). |
| `endReason`      | `EndReason` (enum, see V6)                   | `.userStop | .diskFull | .targetGone | .crashed | .systemSignal`. |
| `wasAbnormalEnd` | `Bool` (computed)                            | `endReason != .userStop`. |
| `presetUsed`     | `RecordingPreset` (snapshot, see E2)         | Snapshot at start; immutable on the Recording. |

**Identity & uniqueness**:

- `id` is the canonical identifier.
- `fileURL` is unique per Recording (file naming guarantees uniqueness via
  timestamp; see `contracts/output-files.md`).

**Persistence**:

- `Recording` is **not persisted in v1** (no recording history view per
  Clarification #2). The information lives in:
  - The file itself (filename + container metadata),
  - The local JSON Lines log (`contracts/logs.md`) — every Recording
    produces exactly one `recording_completed` log entry.
- The implementation MUST be able to reconstruct a `Recording` from a
  fileURL by parsing the filename + container metadata, in case future
  versions (v2+) introduce a history view.

**State transitions** (in-memory only):

```text
   .idle ──start()──▶ .preparing ──streamReady──▶ .recording
                                                       │
                                            ┌──────────┼─────────────────┐
                                            │          │                 │
                                       userStop   diskFull/targetGone   crashed
                                            │          │                 │
                                            ▼          ▼                 ▼
                                      .finalizing  .finalizing     .interrupted
                                            │          │
                                            ▼          ▼
                                         .saved    .saved (with wasAbnormalEnd=true)
```

Invariants:

- A `Recording` can only become `.saved` from `.finalizing` (never directly
  from `.recording`) — guarantees the file has been flushed before the
  "已保存" notification fires (FR-002 / FR-003).
- `.interrupted` does **not** produce a `.saved` Recording in v1 (matches
  Clarification #3 — no crash recovery promise).

---

## E2. `RecordingPreset`

A reusable set of recording configuration values.

| Field           | Type                  | Default                    | Validation |
|-----------------|-----------------------|----------------------------|------------|
| `name`          | `String`              | `"_lastUsed"` (隐式)       | ≤ 64 chars; immutable for `_lastUsed`. |
| `mode`          | `RecordingMode`       | `.video`                   | — |
| `target`        | `TargetTemplate`      | `.fullScreenMain`          | See V7 below. |
| `audioSources`  | `AudioSourceSet`      | `{ ambient: true, system: false }` | At least one must be `true` if `mode == .audioOnly`. |
| `videoConfig`   | `VideoConfig`         | `{ .res1080p, .mp4 }`      | Required only when `mode == .video`. |

**Persistence**:

- `_lastUsed` preset is **always persisted** to `UserDefaults` after every
  successful recording start; it's how the app remembers the user's last
  choices across launches (FR-015).
- Named presets (multi-preset management) are **out of scope for v1** —
  reserved as a future iteration (see Assumptions in spec.md). The data
  model already supports them so v2+ requires no breaking change.

**Identity**: `name` is unique within the user's preset list.

---

## E3. `Settings`

Global, app-wide preferences that are not per-recording.

| Field                       | Type                | Default                                | Validation |
|-----------------------------|---------------------|----------------------------------------|------------|
| `defaultSaveDirectoryURL`   | `URL`               | `~/Movies/Good Recording/`             | Must be writable; if user-selected, persisted as security-scoped bookmark. |
| `audioOnlySaveDirectoryURL` | `URL?`              | `nil` → fall back to `defaultSaveDirectoryURL` | Same validation. |
| `defaultPreset`             | `RecordingPreset`   | E2 defaults                            | Used when `_lastUsed` does not exist. |
| `showMenuBarTimer`          | `Bool`              | `true`                                 | FR-004 toggle (设置中可关). |
| `fileNameTemplate`          | `String`            | `"Recording {date} {time}"`            | v1 fixed; user-customizable in v2+. |
| `notificationsEnabled`      | `Bool`              | `true`                                 | If false, in-app banner replaces system notification. |
| `restoreDefaultsRequested`  | `Bool` (transient)  | `false`                                | UI flag for FR-016 confirmation flow. |

**Persistence**: `UserDefaults` (sandbox container).

**Validation rules**:

- Setting `defaultSaveDirectoryURL` to a non-writable path MUST be rejected
  by the UI before persisting (settings-level acceptance test).
- "Restore Defaults" (FR-016) MUST require explicit user confirmation
  before resetting any field other than `restoreDefaultsRequested`.

---

## V1. `RecordingMode` (enum)

```swift
enum RecordingMode: String, Codable {
    case video
    case audioOnly
}
```

---

## V2. `RecordingTarget` (enum with associated values)

```swift
enum RecordingTarget: Equatable {
    case fullScreen(displayID: CGDirectDisplayID)
    case window(WindowSnapshot)
    case region(CGRect)             // points, not pixels; converted at capture time
}

struct WindowSnapshot: Equatable, Codable {
    let windowID: CGWindowID
    let appBundleID: String
    let windowTitle: String         // captured at start, used in log + filename hint
}
```

Validation:

- `.fullScreen.displayID` MUST refer to a currently connected display at
  start; otherwise UI MUST re-prompt.
- `.window.windowID` MUST refer to a still-existing window at start; if it
  disappears mid-recording → triggers `EndReason.targetGone`.
- `.region.rect` MUST be non-empty and intersect at least one connected
  display.

---

## V3. `AudioSourceSet`

```swift
struct AudioSourceSet: Equatable, Codable {
    var ambient: Bool       // 当前默认音频输入设备 (i.e. mic)
    var system: Bool        // SCK 系统音

    var any: Bool { ambient || system }
}
```

Validation:

- For `RecordingMode.audioOnly`: `any == true` is required at start
  (FR-018). UI MUST block start otherwise.
- For `RecordingMode.video`: `any == false` is allowed (silent video) and
  produces a legal silent audio track (Edge Case in spec.md).

---

## V4. `VideoConfig`

```swift
struct VideoConfig: Equatable, Codable {
    var resolution: VideoResolution     // .res720p / .res1080p / .res1440p / .native
    var container: ContainerFormat      // .mp4 (default) | .mov
    var codec: VideoCodec               // .h264 (default) | .hevc; valid only when container == .mov
}

enum VideoResolution: String, Codable {
    case res720p, res1080p, res1440p, native
}

enum VideoCodec: String, Codable {
    case h264, hevc
}
```

Validation:

- `(container: .mp4, codec: .hevc)` is rejected by the UI (mp4 + HEVC has
  patent / compatibility caveats v1 doesn't want to handle).
- If a user-saved config becomes invalid on a future macOS where the codec
  is no longer supported (FR-014 edge), settings layer MUST silently fall
  back to `(.mp4, .h264, .res1080p)` and surface a one-time notice.

---

## V5. `ContainerFormat`

```swift
enum ContainerFormat: String, Codable {
    case mp4, mov, m4a

    var fileExtension: String { rawValue }
    var isVideoContainer: Bool { self != .m4a }
}
```

Validation:

- `mode == .audioOnly` requires `containerFormat == .m4a`.
- `mode == .video` requires `containerFormat ∈ {.mp4, .mov}`.

---

## V6. `EndReason`

```swift
enum EndReason: String, Codable {
    case userStop          // 用户主动停止 — 唯一保证 100% 可播放的路径
    case diskFull          // 磁盘空间 < 500 MB
    case targetGone        // 目标窗口被关闭 / 显示器拔出
    case systemSignal      // 系统通知应用退出 (e.g. logout)
    case crashed           // App crash — 不写入 log；下次启动检测残留临时文件
}
```

Mapping back to spec:

- `.userStop` ↔ FR-001 / FR-002 / FR-003 / SC-007 ("用户主动停止 100%
  可播放" 唯一来源)。
- `.diskFull` ↔ Edge Case "磁盘剩余 < 500 MB"；触发 FR-023 自动保存
  + 通知。
- `.targetGone` ↔ US2 AC3、Edge Case "录制期间目标窗口被关闭"。
- `.systemSignal` ↔ Edge Case "系统强制重启 / 注销"。
- `.crashed` ↔ Clarification #3 — v1 不承诺可播放；负责 cleanup 的
  代码会在下次启动时扫描临时目录并清理或询问用户。

---

## V7. `TargetTemplate` (preset 用)

```swift
enum TargetTemplate: Codable {
    case fullScreenMain                       // 主显示器
    case fullScreenLastSelected               // 上次选过的某块显示器
    case windowLastSelected                   // 上次选过的窗口（按 bundleID 模糊匹配）
    case regionLastSelected(CGRect)           // 上次画过的矩形
    case promptEachTime                       // 每次录制都打开 picker
}
```

Default: `.promptEachTime`（首次安装），用户做出第一次选择后，
`_lastUsed` preset 被更新为对应具体值。

---

## Cross-entity rules

1. **One active Recording at a time** — UI MUST disable "开始录制" while
   any Recording is in `.preparing | .recording | .finalizing`.
2. **No persisted Recording history** — by design (Clarification #2). The
   only persistent traces are the file on disk + the JSON log entry.
3. **Settings is the single source of truth for defaults** — every
   Recording snapshots the relevant fields into `presetUsed` at start, so
   later setting changes never retroactively mutate past Recordings.
4. **All entities are Codable** — for future export/import (`Settings`
   export will land in v2+; struct shapes already support it).

---

## Migration / forward compatibility

- All `Codable` types use **explicit `String` `rawValue`s** for enums to
  keep on-disk persistence forward-compatible (adding a case won't break
  decoding of older preset / settings files when accompanied by a default
  case in switch statements).
- Adding a 4th `EndReason` case (e.g. `.userPaused` if pause/resume lands
  in v2) requires no migration.
- Adding named presets (E2 multi-preset list in v2) requires only adding a
  `[RecordingPreset]` to `Settings`; the existing `_lastUsed` semantics
  remain unchanged.
