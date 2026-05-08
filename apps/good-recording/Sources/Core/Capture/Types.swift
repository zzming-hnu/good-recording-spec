// good-recording — Core/Capture/Types.swift (T013)
//
// Foundational value types shared by every recording-related code path.
// Source of truth: home-spec/specs/001-good-recording/data-model.md V1–V7.
// Stay in sync — any change here MUST be reflected there in the same PR.

import Foundation
import CoreGraphics

// MARK: - V1. RecordingMode

/// 用户当次录制的目标产物类型。
public enum RecordingMode: String, Codable, Sendable, CaseIterable {
    case video       // 录屏（含可选音频）
    case audioOnly   // 仅录音 (US5)
}

// MARK: - V2. RecordingTarget

/// 单次录制的画面来源选择。`audioOnly` 模式下整个值为 `nil`。
public enum RecordingTarget: Equatable, Sendable, Codable {
    case fullScreen(displayID: CGDirectDisplayID)
    case window(WindowSnapshot)
    case region(CGRect)   // 单位 = points；采集时由 Coordinator 转 pixels

    /// 给日志 / 文件命名 / metadata 用的人类可读简述。
    public var humanLabel: String {
        switch self {
        case .fullScreen:        return "全屏"
        case .window(let snap):  return snap.windowTitle
        case .region(let rect):  return "区域 \(Int(rect.width))×\(Int(rect.height))"
        }
    }
}

/// 一个被选中作为录制目标的窗口在「点击开始的瞬间」的快照。
/// 关闭/最小化后用 `windowID` 检测；显示给人看用 `windowTitle`。
public struct WindowSnapshot: Equatable, Sendable, Codable {
    public let windowID: CGWindowID
    public let appBundleID: String
    public let windowTitle: String

    public init(windowID: CGWindowID, appBundleID: String, windowTitle: String) {
        self.windowID = windowID
        self.appBundleID = appBundleID
        self.windowTitle = windowTitle
    }
}

// MARK: - V3. AudioSourceSet

/// 两个独立的音频源开关。
public struct AudioSourceSet: Equatable, Sendable, Codable {
    public var ambient: Bool   // 系统当前默认音频输入设备 (mic)
    public var system: Bool    // SCK 系统音

    public init(ambient: Bool, system: Bool) {
        self.ambient = ambient
        self.system = system
    }

    /// 任意一个开关打开。
    public var any: Bool { ambient || system }

    /// 两个都关 — silent video / 不可用于 audio-only 模式。
    public var none: Bool { !any }

    public static let allOff  = AudioSourceSet(ambient: false, system: false)
    public static let micOnly = AudioSourceSet(ambient: true,  system: false)
    public static let sysOnly = AudioSourceSet(ambient: false, system: true)
    public static let both    = AudioSourceSet(ambient: true,  system: true)

    /// 默认偏好（首次安装、未做过任何选择时）。
    public static let `default` = micOnly
}

// MARK: - V6. EndReason

/// 录制结束的原因。**只有 `.userStop` 才被 v1 承诺为 100% 可播放**
/// (Clarification #3, spec.md SC-007)。
public enum EndReason: String, Codable, Sendable, CaseIterable {
    case userStop          // 用户主动停止 (主按钮 / 菜单栏 / 热键)
    case diskFull          // 磁盘剩余 < 500 MB → FR-023 触发
    case targetGone        // 窗口被关闭 / 显示器拔出
    case systemSignal      // 系统通知应用退出 (logout / restart)
    case crashed           // App 崩溃 — 不写日志，下次启动扫残留
}

extension EndReason {
    /// 是否为「正常路径」(用户主动)。
    public var isNormal: Bool { self == .userStop }

    /// 是否需要给用户 push 一条系统通知。
    public var requiresNotification: Bool {
        switch self {
        case .userStop:                                    return true
        case .diskFull, .targetGone, .systemSignal:        return true
        case .crashed:                                     return false
        }
    }
}

// MARK: - V7. TargetTemplate (preset 用的范围记忆)

/// 录制范围在 preset 里以「模板」形式保存，保证 preset 跨重启稳定可用。
public enum TargetTemplate: Equatable, Sendable, Codable {
    case fullScreenMain                   // 主显示器
    case fullScreenLastSelected           // 上次选过的某块显示器
    case windowLastSelected               // 上次选的窗口（按 bundleID 模糊匹配）
    case regionLastSelected(CGRect)       // 上次画过的矩形
    case promptEachTime                   // 每次录制都打开 picker

    /// 默认 — 首次安装时使用。
    public static let `default` = TargetTemplate.promptEachTime
}

// MARK: - Capture state machine (data-model.md E1 state diagram)

/// CaptureCoordinator 暴露的 actor-isolated 状态。UI / VM 通过订阅这个状态
/// 驱动 MainWindow 的子状态。
public enum CaptureState: Sendable, Equatable {
    case idle
    case preparing
    case recording(startedAt: Date)
    case finalizing
    case saved(fileURL: URL, endReason: EndReason)
    case interrupted(reason: EndReason)   // 非 `.userStop`，文件可能不可播
    case errorPermission(missing: Permission)
    case errorRuntime(message: String)
}

/// 缺失的权限种类 — 用来驱动 PermissionCardView (S7) 的拷贝。
public enum Permission: String, Sendable, Equatable, CaseIterable {
    case screenRecording
    case microphone
    case notifications

    public var humanName: String {
        switch self {
        case .screenRecording:  return "屏幕录制"
        case .microphone:       return "麦克风"
        case .notifications:    return "通知"
        }
    }

    /// 跳转 macOS 系统设置对应面板的 `x-apple.systempreferences:` URL.
    public var systemSettingsDeeplink: URL {
        switch self {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .notifications:
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        }
    }
}
