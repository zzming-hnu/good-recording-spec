// good-recording — Features/US2-ScopeSelection/WindowPickerViewModel.swift (T058 partial)
//
// ViewModel for the window picker overlay (S5).
// Provides incremental search/filter over currently visible windows.
//
// Source of truth: contracts/ui-surfaces.md S5

import Foundation
import SwiftUI
@preconcurrency import ScreenCaptureKit

@MainActor
public final class WindowPickerViewModel: ObservableObject {

    // MARK: Published state

    @Published public var allWindows: [WindowSnapshot] = []
    @Published public var searchText: String = ""

    /// Callback fired when user selects a window — dismisses the picker.
    public var onSelect: ((WindowSnapshot) -> Void)?

    /// Callback fired on Esc — dismisses without changing selection.
    public var onCancel: (() -> Void)?

    // MARK: Computed

    /// Incrementally filtered window list (S5 contract).
    public var filteredWindows: [WindowSnapshot] {
        if searchText.isEmpty { return allWindows }
        let query = searchText.lowercased()
        return allWindows.filter { snap in
            snap.windowTitle.lowercased().contains(query)
            || snap.appBundleID.lowercased().contains(query)
        }
    }

    /// S5: empty state "没有可录制的窗口" + "重新扫描" button.
    public var showsEmptyState: Bool {
        filteredWindows.isEmpty
    }

    // MARK: Actions

    /// Single-click selects + dismisses (S5 contract).
    public func selectWindow(_ snap: WindowSnapshot) {
        onSelect?(snap)
    }

    /// Refresh the window list from SCShareableContent.
    public func refreshWindows() async {
        do {
            let content = try await SCShareableContent.current
            let snapshots = content.windows
                .filter { !$0.title.isNilOrEmpty && $0.isOnScreen }
                .map { win in
                    WindowSnapshot(
                        windowID: win.windowID,
                        appBundleID: win.owningApplication?.bundleIdentifier ?? "",
                        windowTitle: win.title ?? ""
                    )
                }
            allWindows = snapshots
        } catch {
            allWindows = []
        }
    }
}

// MARK: - Helpers

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}
