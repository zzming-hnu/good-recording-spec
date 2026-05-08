// good-recording — App/MainWindow.swift (T029)
//
// SwiftUI shell that hosts the actual recording UI. The `MainWindowView`
// is intentionally thin: it delegates to MainWindowContent (US1, see T039).
//
// Source of truth: home-spec/specs/001-good-recording/contracts/ui-surfaces.md S1

import SwiftUI

struct MainWindowView: View {
    var body: some View {
        // US1's MainWindowContent (T039) plugs in here. Until then we render
        // a Phase 2 status placeholder that reflects the state machine has
        // wired up — but not yet bound to UI.
        MainWindowContent()
    }
}

// Placeholder fall-through view used until T039 lands a real implementation.
// Kept here (not in Sources/Features/US1-Recording) so Sources/App can
// always build standalone. T039 replaces this struct's body with the real
// US1 binding.
struct MainWindowContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "record.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("App.Title")
                .font(.title)
            Text("App.Subtitle")
                .foregroundStyle(.secondary)
            Text(verbatim: "Phase 2 Foundational ready · US1 一键录屏 lands in T039 (Phase 3).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
