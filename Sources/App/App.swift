// good-recording — main app entry point.
// Phase 1 placeholder. Real US1 (录屏) UI lands in T039 (MainWindowContent.swift)
// per home-spec/specs/001-good-recording/contracts/ui-surfaces.md S1.

import SwiftUI

@main
struct GoodRecordingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(String(localized: "App.Title")) {
            ContentView()
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowResizability(.contentMinSize)
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("App.Title")
                .font(.title)
            Text("App.Subtitle")
                .foregroundStyle(.secondary)
            Text(verbatim: "Phase 1 skeleton — US1 UI lands in T039.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
