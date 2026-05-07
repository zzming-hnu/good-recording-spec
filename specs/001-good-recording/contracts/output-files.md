# Contract: Output Files

**Feature**: 001-good-recording
**Date**: 2026-05-07

This contract defines the on-disk artifact produced by every recording.
It is the source of truth for file naming, save location, container
metadata, and the validations a Recording must pass before being shown
to the user as "已保存" (FR-002, FR-003, SC-007).

---

## File naming template (FR-022)

```text
Recording {YYYY-MM-DD} {HH.MM.SS}.{ext}
```

- `{YYYY-MM-DD}` and `{HH.MM.SS}` use **local time** with explicit
  `:` → `.` substitution (so the filename is Finder-safe across
  case-insensitive HFS+ / APFS).
- `{ext}` is determined by `Recording.containerFormat`:

| Mode        | Default container | Filename example                           |
|-------------|-------------------|--------------------------------------------|
| 录屏（mp4） | `mp4`             | `Recording 2026-05-07 20.12.33.mp4`        |
| 录屏（mov） | `mov`             | `Recording 2026-05-07 20.12.33.mov`        |
| 仅录音      | `m4a`             | `Recording 2026-05-07 20.12.33.m4a`        |

### Collision handling

- If a file with the exact target name already exists (e.g. user changed
  system clock back), append ` (N)` before the extension where N is the
  smallest integer ≥ 2 yielding a free name. Example:
  `Recording 2026-05-07 20.12.33 (2).mp4`.
- The template is **not** user-customizable in v1 (Settings.fileNameTemplate
  is read-only and reserved for v2).

---

## Save location (FR-021)

| Mode        | Default location                                 | Customizable via                                       |
|-------------|--------------------------------------------------|--------------------------------------------------------|
| 录屏        | `~/Movies/Good Recording/`                       | Settings → 保存位置 (`NSOpenPanel` + bookmark)         |
| 仅录音      | `Settings.audioOnlySaveDirectoryURL` if set, else `~/Movies/Good Recording/` (NOT `~/Music/...` by default in v1 — single-folder default keeps mental model simple) | Same Settings UI; per-mode override toggle |

### Pre-flight checks (before opening AVAssetWriter)

- The directory exists; create with intermediate directories if absent.
- The directory is writable (≥ 500 MB free space; otherwise UI MUST
  block start with the spec edge-case message).
- For user-selected directories: a security-scoped bookmark MUST be
  resolvable; if the resource is no longer accessible, fall back to the
  default `~/Movies/Good Recording/` and surface a one-time notice.

---

## Container metadata

Every output file MUST carry the following metadata in the container's
standard fields. This is what allows future versions to reconstruct a
`Recording` from the file alone.

### mp4 / mov (`AVAssetWriter` metadata items)

| Key (`AVMetadataKey`)              | Value                                                |
|------------------------------------|------------------------------------------------------|
| `commonKeyTitle`                   | "good-recording"                                     |
| `commonKeyCreator`                 | App version (e.g. `good-recording/1.0.0 (Build 42)`) |
| `commonKeyCreationDate`            | ISO 8601 of `Recording.startedAt`                    |
| `commonKeyDescription`             | JSON blob (UTF-8) of the recording's `presetUsed`    |

### m4a (audio-only)

Same fields as above; `commonKeyArtwork` left empty.

### Why these metadata

- Round-trip: spec.md says "future versions may add a history view";
  having metadata in the file means the v2 history view can be built
  by scanning the directory without any DB.
- Forensics: the user's local logs (see `logs.md`) reference
  `Recording.id`; the metadata lets a support engineer correlate a log
  entry to a file even if the user renames it.

---

## Encoding parameters

Resolved from `Recording.videoConfig` at writer creation.

| `videoConfig.resolution`                | Output frame size (short side) |
|-----------------------------------------|--------------------------------|
| `.res720p`                              | 720 px                         |
| `.res1080p` (default)                   | 1080 px                        |
| `.res1440p`                             | 1440 px                        |
| `.native`                               | Equal to source (display/window/region) |

- Aspect ratio is **always preserved** from source (FR-013 AC1).
- Frame rate: 30 fps (default) for `.res720p` / `.res1080p`;
  60 fps allowed for `.res1440p` and `.native` (configurable in v2; v1
  follows the source's natural rate, capped at 60 fps).
- Bitrate: VideoToolbox `AverageBitRate` heuristic — `~5 Mbps` for 1080p
  H.264, `~10 Mbps` for 1440p H.264, `~3 Mbps` for HEVC equivalents.
- Audio: AAC, 256 kbps stereo, 48 kHz; mixed down from
  ambient + system if both are enabled.

---

## Acceptance contract (the "可播放" guarantee, SC-007)

A file is "delivered to the user" only after **all** of these checks pass
in `finalizing`:

1. `AVAssetWriter.finishWriting()` succeeds with `.completed` status.
2. `AVURLAsset(url:)` instantiated from the file decodes its track count
   ≥ 1 (video container) or ≥ 1 audio track (m4a).
3. `AVAsset.duration` is finite and `≥ 0.5 s` (avoid empty file edge
   case).
4. The file is `> 0` bytes and `<` available disk space at start.

If any check fails:

- The "已保存" notification is **not** fired.
- The errored file is moved to a sibling quarantine subdirectory
  `~/Movies/Good Recording/_failed/{id}.{ext}` and the user is shown an
  inline error in `MainWindow`.

---

## File lifecycle (in-flight artifacts)

While recording, the writer writes to a temporary file:

```text
~/Library/Containers/<bundle-id>/Data/tmp/recording-{id}.{ext}.partial
```

On successful finalize → atomic move (`FileManager.replaceItemAt`) to the
final location. On crash, the `.partial` file is left behind; on next
launch the app sweeps `tmp/` and deletes any orphaned `.partial` files
(matches Edge Case "应用被强制退出").

---

## Forward compatibility

- Adding new container formats (e.g. webm, future Apple formats) requires
  only extending `ContainerFormat` enum; this contract's filename and
  metadata schema generalize.
- Adding chapter markers (planned for v2 if pause/resume lands) uses the
  standard `AVMetadataItem` chapter API; no breaking change to v1
  consumers.
