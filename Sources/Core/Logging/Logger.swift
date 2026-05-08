// good-recording — Core/Logging/Logger.swift (T016)
//
// Local-first structured logging:
//   - JSON Lines file under sandbox Library/Logs/GoodRecording/YYYY-MM-DD.log
//   - Mirrored to OSLog for Console.app diagnosability
//   - Day-boundary rotation; 30-day / 100 MB cap (whichever is tighter)
//
// Sources of truth:
//   home-spec/specs/001-good-recording/contracts/logs.md
//   home-spec/.specify/memory/constitution.md (Principle V)

import Foundation
import OSLog

// MARK: - Event catalog (mirrors contracts/logs.md exactly)

public enum LogEvent: String, Sendable, Codable {
    // Lifecycle
    case appLaunched         = "app_launched"
    case appTerminating      = "app_terminating"
    case permissionCheck     = "permission_check"
    // Recording
    case recordingRequested  = "recording_requested"
    case recordingStarted    = "recording_started"
    case recordingStopped    = "recording_stopped"
    case recordingFailed     = "recording_failed"
    case targetWindowLost    = "target_window_lost"
    case diskSpaceLow        = "disk_space_low"
    // Audio
    case audioDeviceChanged  = "audio_device_changed"
    case audioMixOverflow    = "audio_mix_overflow"
    // Hotkey
    case hotkeyRegisterOK    = "hotkey_register_succeeded"
    case hotkeyRegisterFail  = "hotkey_register_failed"
    case hotkeyTriggered     = "hotkey_triggered"
    // Settings
    case settingsChanged     = "settings_changed"
    case settingsReset       = "settings_reset"
}

public enum LogLevel: String, Sendable, Codable {
    case debug, info, warn, error
}

// MARK: - The Logger actor

public actor Logger {
    public static let shared = Logger()

    /// 进程 session id（一个 launch 一个 UUID）。
    private let sessionID = UUID().uuidString

    /// 当前 ISO 短日期 (YYYY-MM-DD)，跨天时切换。
    private var currentDate: String = Logger.localDateString(Date())

    /// 当前正在写的文件 handle。
    private var fileHandle: FileHandle?

    /// 应用版本（从 Info.plist 取）。
    private let appVersion: String
    private let buildNumber: String
    private let osVersion: String

    /// 镜像到 OSLog —— 让开发者能在 Console.app 直接看到。
    nonisolated private let osLog = OSLog(
        subsystem: "com.zzming.good-recording",
        category: "all"
    )

    /// 日志根目录（沙箱内）。
    public nonisolated static var logsDirectoryURL: URL {
        let base = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("Logs/GoodRecording", isDirectory: true)
    }

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        self.appVersion = (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        self.buildNumber = (info["CFBundleVersion"] as? String) ?? "0"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        self.osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: Public API

    /// 主入口 — `log(.recordingStarted, .info, ["recording_id": id])`。
    public func log(
        _ event: LogEvent,
        _ level: LogLevel = .info,
        _ extra: [String: Any] = [:]
    ) {
        let record = makeRecord(event: event, level: level, extra: extra)
        writeJSONLine(record)
        mirrorToOSLog(level: level, event: event, record: record)

        // Once-an-hour rotation/prune (cheap, just a guard).
        rotateIfNeeded()
    }

    /// 用户在「设置 → 数据与日志 → 清空日志」点击后调用。
    public func clearAllLogs() {
        let dir = Self.logsDirectoryURL
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) {
            for u in urls { try? FileManager.default.removeItem(at: u) }
        }
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: Private

    private func makeRecord(
        event: LogEvent,
        level: LogLevel,
        extra: [String: Any]
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "ts":          Self.iso8601(Date()),
            "level":       level.rawValue,
            "event":       event.rawValue,
            "session_id":  sessionID,
            "app_version": appVersion,
            "build":       Int(buildNumber) ?? 0,
            "macos":       osVersion
        ]
        for (k, v) in extra { dict[k] = v }
        return dict
    }

    private func writeJSONLine(_ record: [String: Any]) {
        ensureFileHandle()
        guard let handle = fileHandle else { return }
        guard
            let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        else { return }
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data("\n".utf8))
    }

    private func ensureFileHandle() {
        let today = Self.localDateString(Date())
        if today != currentDate {
            try? fileHandle?.close()
            fileHandle = nil
            currentDate = today
        }
        if fileHandle == nil {
            let dir = Self.logsDirectoryURL
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let url = dir.appendingPathComponent("\(today).log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: url)
            if let h = fileHandle { _ = try? h.seekToEnd() }
        }
    }

    private nonisolated func mirrorToOSLog(
        level: LogLevel,
        event: LogEvent,
        record: [String: Any]
    ) {
        let type: OSLogType = switch level {
        case .debug: .debug
        case .info:  .info
        case .warn:  .default
        case .error: .error
        }
        os_log(
            type,
            log: osLog,
            "%{public}@ %{public}@",
            event.rawValue,
            (record["recording_id"] as? String) ?? ""
        )
    }

    /// 按天/大小 cap 清理旧文件。每次 log 调用都会跑（非常便宜）。
    private func rotateIfNeeded() {
        let dir = Self.logsDirectoryURL
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )
        else { return }

        let now = Date()
        let cutoff = now.addingTimeInterval(-30 * 24 * 3600)   // 30 days
        var totalSize: Int = 0

        let sorted = urls.sorted { (a, b) -> Bool in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey])
                .creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey])
                .creationDate) ?? .distantPast
            return da > db   // newest first
        }

        for u in sorted {
            let attrs = try? u.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let date = attrs?.creationDate ?? .distantPast
            let size = attrs?.fileSize ?? 0
            totalSize += size
            let tooOld = date < cutoff
            let tooBig = totalSize > 100 * 1024 * 1024
            if tooOld || tooBig {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }

    // MARK: Helpers

    /// Per-call formatter — Swift 6 strict concurrency forbids sharing
    /// `ISO8601DateFormatter` (it's not Sendable). Construction is cheap
    /// relative to the file write that follows, so this is a non-issue.
    private static func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
            .withTimeZone
        ]
        return f.string(from: d)
    }

    private static func localDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
