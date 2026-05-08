// good-recording — App/App.swift (T028)
//
// SwiftUI App entry point. Hosts the MainWindow + standard macOS commands.

import SwiftUI

@main
struct GoodRecordingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(String(localized: "App.Title")) {
            MainWindowView()
                .frame(minWidth: 480, minHeight: 360)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 good-recording") {
                    // T104 — AboutWindow lands in Phase 8 Polish.
                }
            }
        }
    }
}
