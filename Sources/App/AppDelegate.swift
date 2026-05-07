// good-recording — NSApplicationDelegate.
// Phase 1 placeholder. Future hooks:
//   - T044: MenuBarStatusItem lifecycle
//   - T107: orphan .partial cleanup at launch
// See: home-spec/specs/001-good-recording/contracts/ui-surfaces.md (S4)
//      home-spec/specs/001-good-recording/contracts/output-files.md (tmp lifecycle)

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // T107 will sweep ~/Library/Containers/<bundle-id>/Data/tmp/recording-*.partial here.
        // T044 will install the menu bar NSStatusItem lifecycle here.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Quit when the main window closes (no menu-bar–only mode in v1).
        true
    }
}
