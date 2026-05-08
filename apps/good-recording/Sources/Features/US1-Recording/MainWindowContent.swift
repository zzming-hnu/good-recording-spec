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

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)

                // App identity (v0.1: hard-coded zh-Hans;
                // i18n via Localizable.xcstrings is a Phase 8 Polish task)
                VStack(spacing: 4) {
                    Text(verbatim: "Good Recording")
                        .font(.system(size: 28, weight: .semibold))
                    Text(verbatim: "本地优先的屏幕与音频录制")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
}

