// good-recording — Core/Encoding/EncodingTypes.swift (T014)
//
// Source of truth: home-spec/specs/001-good-recording/data-model.md V4–V5
// + contracts/output-files.md (encoding parameters table).

import Foundation
import AVFoundation
import CoreMedia

// MARK: - V5. ContainerFormat

public enum ContainerFormat: String, Codable, Sendable, CaseIterable {
    case mp4
    case mov
    case m4a   // 仅录音模式专用

    public var fileExtension: String { rawValue }

    public var isVideoContainer: Bool { self != .m4a }

    /// AVFileType for AVAssetWriter.
    public var avFileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        case .m4a: return .m4a
        }
    }

    /// 选定 mode 时哪些容器是合法的。
    public static func validContainers(for mode: RecordingMode) -> [ContainerFormat] {
        switch mode {
        case .video:     return [.mp4, .mov]
        case .audioOnly: return [.m4a]
        }
    }
}

// MARK: - V4. VideoCodec

public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264
    case hevc

    /// AVFoundation 的 codec key.
    public var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }

    /// VideoToolbox 硬件加速一般默认开启；这里给 settings dict 用。
    public var profileLevel: String {
        switch self {
        case .h264: return AVVideoProfileLevelH264MainAutoLevel
        case .hevc: return "HEVC_Main_AutoLevel" as String   // 占位，VideoToolbox 自选
        }
    }
}

// MARK: - V4. VideoResolution

public enum VideoResolution: String, Codable, Sendable, CaseIterable {
    case res720p
    case res1080p
    case res1440p
    case native    // 与源同尺寸

    /// 作为人类可读 label 在设置 UI 里显示。
    public var humanLabel: String {
        switch self {
        case .res720p:  return "720p"
        case .res1080p: return "1080p"
        case .res1440p: return "1440p"
        case .native:   return "原生"
        }
    }

    /// 短边像素数；`.native` 返回 nil 表示「跟随源」。
    public var shortSidePixels: Int? {
        switch self {
        case .res720p:  return 720
        case .res1080p: return 1080
        case .res1440p: return 1440
        case .native:   return nil
        }
    }
}

// MARK: - V4. VideoConfig

/// 录屏的视频参数三元组（仅在 `RecordingMode.video` 时使用）。
public struct VideoConfig: Equatable, Sendable, Codable {
    public var resolution: VideoResolution
    public var container:  ContainerFormat
    public var codec:      VideoCodec

    public init(resolution: VideoResolution, container: ContainerFormat, codec: VideoCodec) {
        self.resolution = resolution
        self.container  = container
        self.codec      = codec
    }

    /// 默认 — mp4 + H.264 + 1080p，开箱在 QuickTime 即可播 (SC-004)。
    public static let `default` = VideoConfig(
        resolution: .res1080p,
        container:  .mp4,
        codec:      .h264
    )

    /// 校验组合是否合法（v1 拒绝 `.mp4 + .hevc` 组合，避免兼容性踩坑）。
    public var isValid: Bool {
        !(container == .mp4 && codec == .hevc)
    }

    /// 不合法时给出最近的合法 fallback（用于 FR-014 自动回退）。
    public func legalizedFallback() -> VideoConfig {
        guard !isValid else { return self }
        return Self.default
    }
}

// MARK: - Bitrate heuristic

/// 给 AVAssetWriter 写 settings dict 时用。
/// 数值参考 contracts/output-files.md:「Encoding parameters」一节。
public enum BitrateHeuristic {
    public static func averageBitsPerSecond(for config: VideoConfig) -> Int {
        switch (config.resolution, config.codec) {
        case (.res720p,  .h264): return 2_500_000
        case (.res720p,  .hevc): return 1_500_000
        case (.res1080p, .h264): return 5_000_000
        case (.res1080p, .hevc): return 3_000_000
        case (.res1440p, .h264): return 10_000_000
        case (.res1440p, .hevc): return 6_000_000
        case (.native,   .h264): return 12_000_000   // 上限
        case (.native,   .hevc): return 8_000_000
        }
    }
}

// MARK: - Audio constants

/// 音频统一规格 — AAC 256 kbps stereo 48 kHz；
/// 来自 contracts/output-files.md 「Encoding parameters」尾注。
public enum AudioFormat {
    public static let sampleRate: Double      = 48_000
    public static let channels: Int           = 2
    public static let bitRate: Int            = 256_000
    public static let codec: AudioFormatID    = kAudioFormatMPEG4AAC
}
