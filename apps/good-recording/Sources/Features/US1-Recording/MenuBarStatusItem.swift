// good-recording — Features/US1-Recording/MenuBarStatusItem.swift (T044)
//
// macOS NSStatusItem shown only while recording. Has a red dot icon, a
// timer label, and a menu with 停止 / 显示主窗口 actions.
//
// Source of truth: home-spec/specs/001-good-recording/contracts/ui-surfaces.md S4

import AppKit
import Combine

@MainActor
final class MenuBarStatusItem {
    static let shared = MenuBarStatusItem()

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var startedAt: Date?

    private init() {}

    func showRecording(startedAt: Date) {
        self.startedAt = startedAt

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
            buildMenu()
        }

        updateTitle()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
    }

    func hide() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        startedAt = nil
    }

    /// Wired by RecordingViewModel — invoked when user clicks the menu item.
    var onStopClicked: (() -> Void)?
    var onShowMainWindowClicked: (() -> Void)?

    // MARK: Private

    private func buildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let stop = NSMenuItem(title: "停止录制", action: #selector(stopAction(_:)), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        let show = NSMenuItem(title: "显示主窗口", action: #selector(showMainAction(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        statusItem.menu = menu

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "good-recording 正在录制")
            button.image?.isTemplate = false
            // Tint red via NSImage symbol configuration
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = button.image?.withSymbolConfiguration(cfg)
        }
    }

    private func updateTitle() {
        guard let item = statusItem, let started = startedAt else { return }
        let secs = Int(Date().timeIntervalSince(started))
        let mm = secs / 60
        let ss = secs % 60
        item.button?.title = String(format: " %02d:%02d", mm, ss)
        item.button?.toolTip = "good-recording 录制中 \(mm) 分 \(ss) 秒"
    }

    @objc private func stopAction(_ sender: Any?) { onStopClicked?() }
    @objc private func showMainAction(_ sender: Any?) {
        onShowMainWindowClicked?()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
    }
}
