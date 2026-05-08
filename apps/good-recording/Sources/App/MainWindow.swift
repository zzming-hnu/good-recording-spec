// good-recording — App/MainWindow.swift (T029)
//
// SwiftUI shell that hosts the actual recording UI. The `MainWindowView`
// is intentionally thin: it delegates to MainWindowContent (US1, see T039).
//
// Source of truth: home-spec/specs/001-good-recording/contracts/ui-surfaces.md S1

import SwiftUI

struct MainWindowView: View {
    var body: some View {
        // The real US1 UI now lives in
        // Sources/Features/US1-Recording/MainWindowContent.swift (T039).
        MainWindowContentView()
    }
}
