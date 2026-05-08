// good-recording — Core/Storage/RecordingFileNamer.swift (T019)
//
// Pure-function file naming + collision handling per the contract:
//   "Recording {YYYY-MM-DD} {HH.MM.SS}.{ext}"
// with " (N)" suffix on collision.
//
// Source of truth: home-spec/specs/001-good-recording/contracts/output-files.md

import Foundation

public enum RecordingFileNamer {

    /// 给定一个目录和一个时刻，返回一个**未冲突的**完整文件路径。
    /// 调用方负责确保目录已存在 + 可写。
    public static func makeFileURL(
        in directory: URL,
        at date: Date,
        format: ContainerFormat,
        clock: Clock = .system
    ) -> URL {
        let baseName = baseName(at: date)
        let ext = format.fileExtension

        let candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        if !clock.fileExists(at: candidate) { return candidate }

        // Collision: append " (2)", " (3)", … until free.
        var n = 2
        while true {
            let url = directory.appendingPathComponent("\(baseName) (\(n)).\(ext)")
            if !clock.fileExists(at: url) { return url }
            n += 1
            if n > 9999 {   // belt-and-braces
                return directory.appendingPathComponent("\(baseName) (\(UUID().uuidString)).\(ext)")
            }
        }
    }

    /// 仅生成 "Recording 2026-05-08 10.06.45" 部分（不含扩展名 + 不含路径）。
    /// 单元测试主要打这一步。
    public static func baseName(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current   // 故意用本地时间，便于 Finder 排序
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"   // ":" → "." 让 HFS+ / APFS 都安全
        return "Recording \(f.string(from: date))"
    }

    /// 临时文件名 (`recording-{uuid}.{ext}.partial`) — 录制中先写到这里，
    /// 完成时 `replaceItemAt` 原子改名到最终位置。
    public static func tempFileURL(
        in directory: URL,
        recordingID: UUID,
        format: ContainerFormat
    ) -> URL {
        directory
            .appendingPathComponent("recording-\(recordingID.uuidString).\(format.fileExtension).partial")
    }
}

// MARK: - Clock injection (for test isolation)

/// 把 `FileManager.fileExists` 抽出来，让 `RecordingFileNamerTests` 不需要
/// touch 真实磁盘也能验证 collision-handling 逻辑。
public protocol Clock: Sendable {
    func fileExists(at url: URL) -> Bool
}

public struct SystemClock: Clock {
    public init() {}
    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

extension Clock where Self == SystemClock {
    public static var system: SystemClock { SystemClock() }
}
