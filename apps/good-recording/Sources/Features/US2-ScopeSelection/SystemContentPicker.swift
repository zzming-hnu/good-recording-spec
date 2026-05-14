// good-recording — Features/US2-ScopeSelection/SystemContentPicker.swift (T057)
//
// Integrates SCContentSharingPicker (macOS 15+) as the primary
// window/region picker. Falls back to self-built pickers (T058/T059)
// when the system picker is unavailable or doesn't cover the case.
//
// Source of truth: research.md R4

import Foundation
@preconcurrency import ScreenCaptureKit
import AppKit

@MainActor
final class SystemContentPicker: NSObject, ObservableObject {

    static let shared = SystemContentPicker()

    @Published private(set) var isPresented: Bool = false

    var onTargetSelected: ((RecordingTarget) -> Void)?

    private override init() {
        super.init()
    }

    /// Present the system content sharing picker.
    @discardableResult
    func present(excluding bundleID: String? = nil) -> Bool {
        let picker = SCContentSharingPicker.shared
        picker.isActive = true

        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow, .singleDisplay]
        if let bid = bundleID {
            config.excludedBundleIDs = [bid]
        }
        picker.defaultConfiguration = config
        picker.present()

        isPresented = true
        return true
    }

    func dismiss() {
        SCContentSharingPicker.shared.isActive = false
        isPresented = false
    }
}
