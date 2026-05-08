// good-recording — App/App.swift (T028)
//
// SwiftUI App entry point. Hosts the MainWindow + standard macOS commands.

import SwiftUI

@main
struct GoodRecordingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // v0.1: hard-code window title in zh-Hans. Localizable.xcstrings
        // path doesn't load reliably under the current sandbox + manual
        // signing setup; full i18n is a Phase 8 Polish task.
        WindowGroup("Good Recording") {
            MainWindowView()
                .frame(minWidth: 480, minHeight: 360)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Good Recording") {
                    // T104 — AboutWindow lands in Phase 8 Polish.
                }
            }
        }
    }
}
