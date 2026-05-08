// good-recording — Core/Notifications/Notifier.swift (T020)
//
// UserNotifications wrapper for the 4 notification types in
// contracts/ui-surfaces.md S10. Falls back to in-app banner via the
// `BannerSink` protocol if notification permission is denied.
//
// Source of truth: home-spec/specs/001-good-recording/contracts/ui-surfaces.md S10

import Foundation
import UserNotifications
import AppKit

// MARK: - In-app banner sink (UI implements this)

@MainActor
public protocol BannerSink: AnyObject {
    func showBanner(title: String, body: String, action: BannerAction?)
}

public struct BannerAction: Sendable {
    public let title: String
    public let perform: @Sendable () -> Void
    public init(title: String, perform: @escaping @Sendable () -> Void) {
        self.title = title
        self.perform = perform
    }
}

// MARK: - Notifier

@MainActor
public final class Notifier {
    public static let shared = Notifier()

    private weak var bannerSink: BannerSink?
    private let center = UNUserNotificationCenter.current()

    private init() {}

    public func attachBannerSink(_ sink: BannerSink) { self.bannerSink = sink }

    // MARK: Public events (S10 catalog)

    public func recordingSaved(fileURL: URL) {
        let title = "已保存"
        let body = fileURL.lastPathComponent
        notify(
            title: title,
            body: body,
            action: BannerAction(title: "在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            },
            categoryID: "RECORDING_SAVED"
        )
    }

    public func recordingAutoStoppedDiskFull(fileURL: URL) {
        notify(
            title: "已自动停止",
            body: "磁盘空间不足，已保存当前录制。",
            action: BannerAction(title: "在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        )
    }

    public func recordingAutoStoppedTargetGone(fileURL: URL) {
        notify(
            title: "已自动停止",
            body: "录制目标已消失，已保存当前录制。",
            action: BannerAction(title: "在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        )
    }

    public func hotkeyUnavailable() {
        notify(
            title: "全局快捷键不可用",
            body: "请使用菜单栏或主窗口的停止按钮。",
            action: nil
        )
    }

    // MARK: Plumbing

    private func notify(
        title: String,
        body: String,
        action: BannerAction?,
        categoryID: String? = nil
    ) {
        // Always mirror to in-app banner so users see something even if they
        // denied system notifications.
        bannerSink?.showBanner(title: title, body: body, action: action)

        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                postSystemNotification(title: title, body: body, categoryID: categoryID)
            default:
                // banner alone is fine
                break
            }
        }
    }

    private func postSystemNotification(title: String, body: String, categoryID: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let cat = categoryID { content.categoryIdentifier = cat }

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // immediate
        )
        center.add(req, withCompletionHandler: nil)
    }
}
