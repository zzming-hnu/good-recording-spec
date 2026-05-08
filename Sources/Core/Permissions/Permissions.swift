// good-recording — Core/Permissions/Permissions.swift (T017)
//
// TCC permission helpers — request just-in-time, never at app launch.
// Source of truth: home-spec/specs/001-good-recording/contracts/permissions.md

import Foundation
import AVFoundation
import ScreenCaptureKit
import UserNotifications
import AppKit

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

    /// 屏幕录制权限：通过尝试 `SCShareableContent.current` 来检测 — 这是
    /// macOS 上唯一可靠的「我现在能不能用 SCK」探测方式。
    public static func screenRecording() async -> PermissionStatus {
        do {
            // SCShareableContent.current 在权限被拒绝时抛错（带特定 code）。
            _ = try await SCShareableContent.current
            return .granted
        } catch {
            // 任何错都视作未授予（更细分类不影响 UX）。
            return .denied
        }
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
