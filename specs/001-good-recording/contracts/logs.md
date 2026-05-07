# Contract: Local Logs

**Feature**: 001-good-recording
**Date**: 2026-05-07

This contract defines the structured-log format and lifecycle the v1
app produces locally. It is the source of truth for the "查看日志" /
"导出日志" / "清空日志" Settings actions and for the constitution
V (本地可观测与可恢复) compliance review.

The logging strategy was justified in `research.md` R9.

---

## Log location & rotation

| Aspect          | Value                                                                     |
|-----------------|---------------------------------------------------------------------------|
| Directory       | `~/Library/Containers/<bundle-id>/Data/Library/Logs/GoodRecording/`       |
| Filename        | `YYYY-MM-DD.log` (one file per local day)                                 |
| Format          | UTF-8 JSON Lines (one valid JSON object per line, `\n` separated)         |
| Rotation        | Day boundary (local time). Logs older than 30 days OR exceeding 100 MB total are pruned at app launch and once per hour while running. |
| User actions    | Settings → 数据与日志 → "查看" (opens dir), "导出" (NSSavePanel → zip), "清空" (twice-confirmed delete) |
| OSLog mirror    | Every entry is also written to `os_log` under subsystem `com.zzming.good-recording`, category = entry's `event` field; visible in Console.app for developers. |

---

## Schema (per JSON Lines entry)

### Common fields (every entry)

```json
{
  "ts": "2026-05-07T20:12:33.512+08:00",
  "level": "info",
  "event": "recording_started",
  "session_id": "BFE5C2D3-...",
  "app_version": "1.0.0",
  "build": 42,
  "macos": "15.4.1"
}
```

| Field         | Type     | Notes                                                          |
|---------------|----------|----------------------------------------------------------------|
| `ts`          | string   | ISO 8601 with milliseconds + timezone offset                   |
| `level`       | enum     | `debug | info | warn | error`                                  |
| `event`       | string   | Stable identifier (snake_case). See event catalog below.       |
| `session_id`  | string   | UUID; one per app launch (not per recording)                   |
| `app_version` | string   | Marketing version                                              |
| `build`       | integer  | Build number                                                   |
| `macos`       | string   | Reported by `ProcessInfo.operatingSystemVersionString`         |

Event-specific fields are documented inline below.

---

## Event catalog (v1)

### Lifecycle

| Event              | Level | Extra fields                                            |
|--------------------|-------|---------------------------------------------------------|
| `app_launched`     | info  | `cold_start_ms`                                         |
| `app_terminating`  | info  | `reason: "user" | "system"`                             |
| `permission_check` | info  | `permission`, `status: granted | denied | not_determined` |

### Recording

| Event                  | Level | Extra fields                                                                                   |
|------------------------|-------|------------------------------------------------------------------------------------------------|
| `recording_requested`  | info  | `recording_id`, `mode`, `target` (`fullScreen|window|region`), `audio_sources`                |
| `recording_started`    | info  | `recording_id`, `actual_resolution`, `container`, `codec`, `audio_codec`, `frame_rate`, `started_at` |
| `recording_stopped`    | info  | `recording_id`, `end_reason`, `duration_ms`, `file_url` (path string), `file_size_bytes`       |
| `recording_failed`     | error | `recording_id`, `phase`, `error_domain`, `error_code`, `error_message`                         |
| `target_window_lost`   | warn  | `recording_id`, `window_app`, `window_title`                                                   |
| `disk_space_low`       | warn  | `free_bytes`, `threshold_bytes`                                                                |

### Audio

| Event                  | Level | Extra fields                                            |
|------------------------|-------|---------------------------------------------------------|
| `audio_device_changed` | warn  | `recording_id`, `from_uid`, `to_uid`                    |
| `audio_mix_overflow`   | error | `recording_id`, `dropped_samples`                       |

### Hotkey

| Event                       | Level | Extra fields                          |
|-----------------------------|-------|---------------------------------------|
| `hotkey_register_succeeded` | info  | `key: "ctrl+shift+k"`                 |
| `hotkey_register_failed`    | warn  | `key`, `reason`                       |
| `hotkey_triggered`          | info  | `recording_id`                        |

### Settings

| Event              | Level | Extra fields                            |
|--------------------|-------|-----------------------------------------|
| `settings_changed` | info  | `field`, `old`, `new`                   |
| `settings_reset`   | info  | (none — confirmation already gated UI)  |

---

## Privacy rules (HARD constraints)

To stay compliant with constitution I (本地优先与隐私保护):

1. **No log entry MAY contain the contents of recorded audio or video**
   (only metadata such as resolution, duration, file path).
2. **No log entry MAY contain user-provided free text**, with the
   exception of:
   - `window_title` — as it appears in macOS window list — kept because
     it's needed for support diagnostics; users SHOULD be informed in
     the privacy section of the About window that window titles are
     logged locally.
3. **No log line is ever sent off-device by default.** The "导出日志"
   action requires explicit user invocation and produces a local zip
   file via `NSSavePanel`; the app never opens a network socket.
4. **Logs MUST be wipeable.** "清空日志" deletes every file in the log
   directory after a confirm alert.

---

## Validation tests

A `LogContractTests` suite MUST verify:

- Every `event` value in the catalog above is emitted at least once
  during a scripted run (one of each).
- Every emitted line parses as valid JSON.
- Every emitted line contains all required common fields.
- No line contains the substrings `password`, `token`, `secret`,
  `bearer` (regression guard).
- Rotation: when the log dir exceeds 100 MB, oldest files are pruned.
- "Clear logs" leaves the directory empty.

---

## Forward compatibility

- Adding a new event requires:
  - Adding a row to the catalog above (this contract).
  - Adding a `LogContractTests` assertion.
  - No schema migration (JSON Lines is naturally append-only).
- Renaming an event requires a MAJOR app version bump and a one-shot
  rewrite at first launch (for the open day's file only — older days
  remain frozen).
