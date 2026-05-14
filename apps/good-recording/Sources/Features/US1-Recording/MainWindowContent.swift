// good-recording — Features/US1-Recording/MainWindowContent.swift (T039)
//
// THE primary view of the app. One big "开始/停止" button, an elapsed-time
// label while recording, the saved-file banner after stopping, and the
// permission card if a TCC permission is missing.
//
// Source of truth: home-spec/specs/001-good-recording/contracts/ui-surfaces.md S1

import SwiftUI

struct MainWindowContentView: View {

    @StateObject private var vm = RecordingViewModel()

    @State private var showWindowPicker = false
    @State private var showRegionPicker = false

    private let windowPickerPanel = WindowPickerPanel()
    private let regionPickerOverlay = RegionPickerOverlay()

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)

                // App identity
                VStack(spacing: 4) {
                    Text("App.Title")
                        .font(.system(size: 28, weight: .semibold))
                    Text("App.Subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // US2 — Range picker (idle state only)
                if !vm.primaryButtonIsRecording && !vm.primaryButtonIsBusy {
                    RangePickerView(
                        vm: vm.rangePicker,
                        onShowWindowPicker: { openWindowPicker() },
                        onShowRegionPicker: { openRegionPicker() }
                    )
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }

                // Recording icon (turns red while recording)
                Image(systemName: vm.primaryButtonIsRecording
                                  ? "record.circle.fill"
                                  : "record.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(vm.primaryButtonIsRecording ? .red : .accentColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: vm.primaryButtonIsRecording)

                // Elapsed time
                if vm.primaryButtonIsRecording {
                    Text(vm.elapsedDescription)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.red)
                        .accessibilityLabel("已录制 \(vm.elapsedDescription)")
                } else {
                    Text(verbatim: " ")
                        .font(.system(.title3, design: .monospaced))
                }

                // Primary button
                Button(action: { vm.toggleRecording() }) {
                    Text(vm.primaryButtonLabel)
                        .font(.headline)
                        .frame(minWidth: 160)
                        .padding(.vertical, 6)
                }
                .keyboardShortcut(.return, modifiers: [])
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(vm.primaryButtonIsRecording ? .red : .accentColor)
                .disabled(vm.primaryButtonIsBusy)
                .help(vm.primaryButtonTooltip)
                .accessibilityLabel(vm.primaryButtonLabel)
                .accessibilityHint("快捷键 Control + Shift + K")

                // Hotkey availability hint
                if !vm.hotkeyAvailable && vm.primaryButtonIsRecording {
                    Text(verbatim: "全局快捷键 ⌃⇧K 不可用，请用此按钮停止")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 8)
            }
            .padding(32)

            // Saved banner (auto-fade after 5s — handled in VM)
            if let savedURL = vm.savedFileURL {
                VStack {
                    Spacer()
                    SavedBannerView(fileURL: savedURL) { vm.showInFinder() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding()
                }
                .animation(.spring(duration: 0.4), value: vm.savedFileURL)
            }

            // Permission card
            if let missing = vm.missingPermission {
                PermissionCardView(
                    missing: missing,
                    onOpenSettings: { vm.openMissingPermissionSettings() },
                    onDismiss:      { vm.dismissPermissionCard() },
                    onRetry:        { vm.retryAfterPermissionGrant() }
                )
                .background(.ultraThinMaterial)
                .transition(.opacity)
            }
        }
    }

    // MARK: US2 — Picker launchers

    private func openWindowPicker() {
        let rangePicker = vm.rangePicker
        let panel = windowPickerPanel
        let pickerVM = WindowPickerViewModel()
        pickerVM.onSelect = { snap in
            rangePicker.selectWindow(snap)
            panel.dismiss()
        }
        pickerVM.onCancel = {
            panel.dismiss()
        }
        panel.show(vm: pickerVM)
    }

    private func openRegionPicker() {
        let rangePicker = vm.rangePicker
        let overlay = regionPickerOverlay
        overlay.initialRect = rangePicker.selectedRegion
        overlay.onRegionSelected = { rect in
            rangePicker.selectRegion(rect)
        }
        overlay.onCancel = {}
        overlay.show()
    }
}

