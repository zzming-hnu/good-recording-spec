// good-recording — Core/Storage/Models.swift (T015)
//
// Source of truth: home-spec/specs/001-good-recording/data-model.md E1–E3.
// Three persisted entities + a few convenience constructors.

import Foundation

// MARK: - E1. Recording

/// 一次录制活动的完整描述（in-memory 模型；不持久化到 DB —— v1 没有
/// 录制历史视图，详见 Clarification #2）。
public struct Recording: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let mode: RecordingMode
    public let startedAt: Date
    public var endedAt: Date?

    public let target: RecordingTarget?           // nil 仅当 .audioOnly
    public let audioSources: AudioSourceSet
    public let videoConfig: VideoConfig?          // nil 仅当 .audioOnly
    public let containerFormat: ContainerFormat

    public var fileURL: URL
    public var fileSizeBytes: Int64
    public var endReason: EndReason?

    /// 启动该录制时使用的 preset 快照（不可变；后续设置改动不会回写）。
    public let presetUsed: RecordingPreset

    public init(
        id: UUID = UUID(),
        mode: RecordingMode,
        startedAt: Date,
        endedAt: Date? = nil,
        target: RecordingTarget?,
        audioSources: AudioSourceSet,
        videoConfig: VideoConfig?,
        containerFormat: ContainerFormat,
        fileURL: URL,
        fileSizeBytes: Int64 = 0,
        endReason: EndReason? = nil,
        presetUsed: RecordingPreset
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.target = target
        self.audioSources = audioSources
        self.videoConfig = videoConfig
        self.containerFormat = containerFormat
        self.fileURL = fileURL
        self.fileSizeBytes = fileSizeBytes
        self.endReason = endReason
        self.presetUsed = presetUsed
    }

    /// 录制时长 (s)，未结束返回到「现在」为止的时长。
    public var duration: TimeInterval {
        let end = endedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }

    /// 是否为「非正常」结束 — 用于过滤 SC-007 统计。
    public var wasAbnormalEnd: Bool {
        guard let r = endReason else { return false }
        return !r.isNormal
    }
}

// MARK: - E2. RecordingPreset

/// 一组可复用的录制配置。v1 实际只持久化一个隐式 `_lastUsed` preset
/// (data-model.md E2)；多 preset 管理是 v2+ 扩展点。
public struct RecordingPreset: Sendable, Codable, Equatable {
    public var name: String                  // ≤ 64 chars; "_lastUsed" 不可改
    public var mode: RecordingMode
    public var target: TargetTemplate
    public var audioSources: AudioSourceSet
    public var videoConfig: VideoConfig      // 仅 mode == .video 时有意义

    public init(
        name: String,
        mode: RecordingMode = .video,
        target: TargetTemplate = .default,
        audioSources: AudioSourceSet = .default,
        videoConfig: VideoConfig = .default
    ) {
        precondition(name.count <= 64, "Preset name must be ≤ 64 chars")
        self.name = name
        self.mode = mode
        self.target = target
        self.audioSources = audioSources
        self.videoConfig = videoConfig
    }

    /// 隐式「上次使用」preset 的固定名字（FR-015 决定的契约）。
    public static let lastUsedName = "_lastUsed"

    /// 工厂 — 出厂默认值。
    /// v1 阶段：默认同时录 mic + system，让用户开箱即得"教学视频/会议录制"
    /// 最常见的双轨场景。Phase 5 (US3) 会引入独立 toggle UI 后，这个
    /// 默认值可以回归到 spec 推荐的 `.micOnly`（隐私最小化）。
    public static let factoryDefault = RecordingPreset(
        name: lastUsedName,
        mode: .video,
        target: .default,
        audioSources: .both,
        videoConfig: .default
    )

    /// 当前 preset 在 v1 audio-only 模式下是否合法（FR-018）：
    /// 至少要有一个音频源，否则 UI 必须 block 开始按钮。
    public func canStartFor(mode runMode: RecordingMode) -> Bool {
        switch runMode {
        case .video:     return true
        case .audioOnly: return audioSources.any
        }
    }
}

// MARK: - E3. Settings

/// 全局应用偏好 — 单例化、持久化到 UserDefaults（沙箱内）。
public struct Settings: Sendable, Codable, Equatable {
    /// 录屏文件默认保存目录。
    public var defaultSaveDirectoryURL: URL
    /// 仅录音文件保存目录；nil = 跟随 defaultSaveDirectoryURL（v1 默认行为）。
    public var audioOnlySaveDirectoryURL: URL?
    /// 出厂默认 preset 的副本；不会随用户改动。
    public var defaultPreset: RecordingPreset
    /// 录制时是否在菜单栏显示计时器（FR-004 用户可关）。
    public var showMenuBarTimer: Bool
    /// 文件命名模板。v1 固定值，v2+ 才允许自定义。
    public let fileNameTemplate: String
    /// 用户是否启用了系统通知。
    public var notificationsEnabled: Bool

    public init(
        defaultSaveDirectoryURL: URL,
        audioOnlySaveDirectoryURL: URL? = nil,
        defaultPreset: RecordingPreset = .factoryDefault,
        showMenuBarTimer: Bool = true,
        fileNameTemplate: String = "Recording {date} {time}",
        notificationsEnabled: Bool = true
    ) {
        self.defaultSaveDirectoryURL = defaultSaveDirectoryURL
        self.audioOnlySaveDirectoryURL = audioOnlySaveDirectoryURL
        self.defaultPreset = defaultPreset
        self.showMenuBarTimer = showMenuBarTimer
        self.fileNameTemplate = fileNameTemplate
        self.notificationsEnabled = notificationsEnabled
    }

    /// 工厂 — 第一次启动时使用 (`~/Movies/Good Recording/`).
    public static func factoryDefault() -> Settings {
        let movies = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        let dir = movies.appendingPathComponent("Good Recording", isDirectory: true)
        return Settings(defaultSaveDirectoryURL: dir)
    }

    /// 给定 `RecordingMode` 解析实际保存目录。
    public func saveDirectory(for mode: RecordingMode) -> URL {
        switch mode {
        case .video:     return defaultSaveDirectoryURL
        case .audioOnly: return audioOnlySaveDirectoryURL ?? defaultSaveDirectoryURL
        }
    }
}
