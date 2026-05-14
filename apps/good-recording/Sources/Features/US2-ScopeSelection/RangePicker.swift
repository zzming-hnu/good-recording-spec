// good-recording — Features/US2-ScopeSelection/RangePicker.swift (T055)
//
// SwiftUI segmented control for recording target selection.
// Three segments: 整个屏幕 / 单个窗口 / 自定义区域
//
// Source of truth: contracts/ui-surfaces.md S2

import SwiftUI

struct RangePickerView: View {

    @ObservedObject var vm: RangePickerViewModel

    /// Called when user taps "选择窗口…"
    var onShowWindowPicker: () -> Void = {}

    /// Called when user taps "选择区域…"
    var onShowRegionPicker: () -> Void = {}

    var body: some View {
        if FeatureFlags.US2_SCOPE_SELECTION {
            VStack(alignment: .leading, spacing: 12) {
                Picker("录制范围", selection: $vm.selectedSegment) {
                    ForEach(RangePickerSegment.allCases) { seg in
                        Text(seg.label).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("RangePicker")

                segmentDetail
            }
        }
    }

    @ViewBuilder
    private var segmentDetail: some View {
        switch vm.selectedSegment {
        case .fullScreen:
            fullScreenDetail

        case .window:
            windowDetail

        case .region:
            regionDetail
        }
    }

    @ViewBuilder
    private var fullScreenDetail: some View {
        if vm.shouldShowDisplayChooser {
            DisplayChooserView(
                selectedDisplayID: $vm.selectedDisplayID,
                displayCount: vm.availableDisplayCount
            )
        } else {
            Text("将录制主显示器的整个屏幕")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var windowDetail: some View {
        HStack {
            if let snap = vm.selectedWindow {
                Label(snap.windowTitle, systemImage: "macwindow")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("重新选择") {
                    onShowWindowPicker()
                }
                .controlSize(.small)
            } else {
                Button("选择窗口…") {
                    onShowWindowPicker()
                }
            }
        }
    }

    @ViewBuilder
    private var regionDetail: some View {
        HStack {
            if let rect = vm.selectedRegion {
                Label("\(Int(rect.width)) × \(Int(rect.height))", systemImage: "rectangle.dashed")
                Spacer()
                Button("重新选择") {
                    onShowRegionPicker()
                }
                .controlSize(.small)
                Button("重置区域") {
                    vm.clearRegion()
                }
                .controlSize(.small)
            } else {
                Button("选择区域…") {
                    onShowRegionPicker()
                }
            }
        }
    }
}
