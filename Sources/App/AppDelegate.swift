// good-recording — App/AppDelegate.swift (T028)
//
// Lifecycle host. Owns first-launch chores:
//   - Bootstraps Logger by emitting `app_launched` with cold_start_ms
//   - Sweeps orphan tmp/recording-*.partial files (T107 stub)
//   - MenuBarStatusItem lifecycle hook (US1 attaches via T044)
//   - Wires Notifier banner sink (US1 attaches via T040 SavedBannerView)

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Set from MainWindow's onAppear so the menu bar can show/hide alongside.
    static let shared = AppDelegate()
    private let coldStartReference: Date = ProcessInfo.processInfo.systemUptime > 0
        ? Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        : Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let elapsedMs = Int(Date().timeIntervalSince(coldStartReference) * 1000)
        Task { await Logger.shared.log(.appLaunched, .info, ["cold_start_ms": elapsedMs]) }

        // Orphan .partial sweep (T107 placeholder behavior)
        sweepOrphanPartials()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await Logger.shared.log(.appTerminating, .info, ["reason": "user"]) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Helpers

    /// Sweeps any leftover tmp/recording-*.partial files. v1: silent delete.
    /// v2+ may show "we found N unfinished recordings — recover or discard?".
    private func sweepOrphanPartials() {
        let tmp = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
        else { return }
        for url in entries
            where url.lastPathComponent.hasPrefix("recording-")
              && url.lastPathComponent.hasSuffix(".partial") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
