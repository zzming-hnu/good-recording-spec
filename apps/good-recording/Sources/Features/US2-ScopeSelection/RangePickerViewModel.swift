// good-recording — Features/US2-ScopeSelection/RangePickerViewModel.swift (T055 partial)
//
// ViewModel for the range picker segmented control (S2).
// Preserves sub-values across segment switches per contract.
//
// Source of truth: contracts/ui-surfaces.md S2

import Foundation
import SwiftUI
import CoreGraphics

// MARK: - Segment enum

public enum RangePickerSegment: String, CaseIterable, Identifiable, Sendable {
    case fullScreen = "fullScreen"
    case window     = "window"
    case region     = "region"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fullScreen: return "整个屏幕"
        case .window:     return "单个窗口"
        case .region:     return "自定义区域"
        }
    }
}

// MARK: - ViewModel

@MainActor
public final class RangePickerViewModel: ObservableObject {

    // MARK: Published state

    @Published public var selectedSegment: RangePickerSegment = .fullScreen

    /// The display chosen when in .fullScreen mode (CGMainDisplayID() by default).
    @Published public var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()

    /// The window snapshot chosen when in .window mode.
    @Published public var selectedWindow: WindowSnapshot?

    /// The region rect chosen when in .region mode.
    @Published public var selectedRegion: CGRect?

    /// Number of connected displays — drives whether DisplayChooser appears.
    @Published public var availableDisplayCount: Int = 1

    // MARK: Computed

    /// S2 contract: display chooser dropdown visible only when >= 2 displays.
    public var shouldShowDisplayChooser: Bool {
        selectedSegment == .fullScreen && availableDisplayCount >= 2
    }

    /// Whether the "选择窗口…" button should appear.
    public var shouldShowWindowPickerButton: Bool {
        selectedSegment == .window
    }

    /// Whether the "选择区域…" button should appear.
    public var shouldShowRegionPickerButton: Bool {
        selectedSegment == .region
    }

    /// Human-readable description of the current selection (for accessibility).
    public var selectionSummary: String {
        switch selectedSegment {
        case .fullScreen:
            return "整个屏幕"
        case .window:
            return selectedWindow?.windowTitle ?? "未选择窗口"
        case .region:
            if let r = selectedRegion {
                return "区域 \(Int(r.width))×\(Int(r.height))"
            }
            return "未选择区域"
        }
    }

    /// Whether we have a valid target to start recording with.
    public var hasValidTarget: Bool {
        switch selectedSegment {
        case .fullScreen: return true
        case .window:     return selectedWindow != nil
        case .region:     return selectedRegion != nil
        }
    }

    // MARK: Actions

    public func selectDisplay(_ displayID: CGDirectDisplayID) {
        selectedDisplayID = displayID
    }

    public func selectWindow(_ snap: WindowSnapshot) {
        selectedWindow = snap
    }

    public func selectRegion(_ rect: CGRect) {
        selectedRegion = rect
    }

    public func clearRegion() {
        selectedRegion = nil
    }

    /// Build a RecordingTarget from the current selection. Returns nil if
    /// the selection is incomplete (e.g. .window with no window picked).
    public func buildTarget() -> RecordingTarget? {
        switch selectedSegment {
        case .fullScreen:
            return .fullScreen(displayID: selectedDisplayID)
        case .window:
            guard let snap = selectedWindow else { return nil }
            return .window(snap)
        case .region:
            guard let rect = selectedRegion else { return nil }
            return .region(rect)
        }
    }

    /// Restore state from a persisted TargetTemplate (Settings._lastUsed).
    public func restoreFromTemplate(_ template: TargetTemplate) {
        switch template {
        case .fullScreenMain:
            selectedSegment = .fullScreen
            selectedDisplayID = CGMainDisplayID()
        case .fullScreenLastSelected:
            selectedSegment = .fullScreen
        case .windowLastSelected:
            selectedSegment = .window
        case .regionLastSelected(let rect):
            selectedSegment = .region
            selectedRegion = rect
        case .promptEachTime:
            selectedSegment = .fullScreen
        }
    }

    /// Build a TargetTemplate for persistence.
    public func buildTemplate() -> TargetTemplate {
        switch selectedSegment {
        case .fullScreen:
            if selectedDisplayID == CGMainDisplayID() {
                return .fullScreenMain
            }
            return .fullScreenLastSelected
        case .window:
            return .windowLastSelected
        case .region:
            if let rect = selectedRegion {
                return .regionLastSelected(rect)
            }
            return .promptEachTime
        }
    }

    // MARK: Display enumeration

    /// Refresh the available display list from CoreGraphics.
    public func refreshDisplays() {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &count)
        availableDisplayCount = Int(count)
    }
}
