// good-recording — Core/Permissions/Permissions.swift (T017)
//
// TCC permission helpers — request just-in-time, never at app launch.
// Source of truth: home-spec/specs/001-good-recording/contracts/permissions.md

import Foundation
import AVFoundation
import ScreenCaptureKit
import UserNotifications
import AppKit
import CoreGraphics

public enum PermissionStatus: String, Sendable {
    case notDetermined
    case denied
    case granted
    case restricted

    public var isGranted: Bool { self == .granted }
}

// MARK: - Public façade

public enum Permissions {

    // MARK: Screen Recording (TCC, no entitlement key)

    /// 屏幕录制权限检测 — 用 Apple 推荐的 `CGPreflightScreenCaptureAccess()`，
    /// 这是同步、不抛错、专门为权限预检设计的轻量 API（不会触发系统对话框）。
    public static func screenRecording() -> PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// 主动请求屏幕录制权限 — 触发 macOS 系统级对话框（如果当前 cdhash
    /// 还没在 TCC 注册过）。返回值是用户**当下**的回应，不一定是最终结果，
    /// 因为系统对话框关闭后用户可能跳到 System Settings 完成授权。
    @discardableResult
    public static func requestScreenRecording() -> PermissionStatus {
        CGRequestScreenCaptureAccess() ? .granted : .denied
    }

    /// 唤起 macOS Settings 的「屏幕录制」面板。
    public static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(Permission.screenRecording.systemSettingsDeeplink)
    }

    // MARK: Microphone

    public static func microphone() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .granted
        @unknown default:    return .denied
        }
    }

    /// 请求麦克风权限（首次会弹系统对话框）。
    public static func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    public static func openMicrophoneSettings() {
        NSWorkspace.shared.open(Permission.microphone.systemSettingsDeeplink)
    }

    // MARK: Notifications

    public static func notifications() async -> PermissionStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        case .authorized, .provisional, .ephemeral: return .granted
        @unknown default:    return .denied
        }
    }

    /// 请求通知权限（首次成功录制完成后调用一次；拒绝后永不再问）。
    public static func requestNotifications() async -> PermissionStatus {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        return granted ? .granted : .denied
    }

    public static func openNotificationSettings() {
        NSWorkspace.shared.open(Permission.notifications.systemSettingsDeeplink)
    }
}
