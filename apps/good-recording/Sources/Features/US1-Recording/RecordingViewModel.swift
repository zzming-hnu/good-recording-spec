// good-recording — Features/US1-Recording/RecordingViewModel.swift (T038)
//
// THE single ViewModel that drives MainWindowContent for US1. Owns the
// CaptureCoordinator and translates its actor-isolated state into
// SwiftUI-friendly @Published properties.
//
// Source of truth:
//   home-spec/specs/001-good-recording/contracts/ui-surfaces.md S1
//   home-spec/specs/001-good-recording/spec.md US1 + FR-001..FR-029

import Foundation
import SwiftUI
import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
final class RecordingViewModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var savedFileURL: URL?
    @Published private(set) var missingPermission: Permission?
    @Published private(set) var hotkeyAvailable: Bool = true
    @Published private(set) var elapsedDescription: String = "00:00"

    /// US2 — range picker view model (owns the target selection state).
    @Published var rangePicker = RangePickerViewModel()

    // MARK: Computed UI

    var primaryButtonLabel: String {
        switch state {
        case .recording, .finalizing: return "停止录制"
        default:                       return "开始录制"
        }
    }

    var primaryButtonIsRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var primaryButtonIsBusy: Bool {
        switch state {
        case .preparing, .finalizing: return true
        default: return false
        }
    }

    /// Tooltip for the primary button — discloses the global hotkey (FR-028).
    var primaryButtonTooltip: String {
        switch state {
        case .recording, .finalizing: return "停止录制 (⌃⇧K)"
        default:                       return "开始录制 (⌃⇧K)"
        }
    }

    // MARK: Internal

    private let coordinator: CaptureCoordinator
    private let settings: SettingsStore
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var targetWatcherTask: Task<Void, Never>?
    private var displayChangeObserver: Any?

    /// Test seam — set via env var GOOD_RECORDING_FAKE_PERMISSION_DENIED=1
    private var fakePermissionDenied: Bool {
        ProcessInfo.processInfo.environment["GOOD_RECORDING_FAKE_PERMISSION_DENIED"] == "1"
    }

    init(coordinator: CaptureCoordinator = CaptureCoordinator(),
         settings: SettingsStore = .shared) {
        self.coordinator = coordinator
        self.settings = settings

        // Wire the actor's state into our @Published mirror.
        Task { [weak self] in
            await coordinator.setOnStateChange { [weak self] new in
                Task { @MainActor in self?.applyState(new) }
            }
        }

        // US2 T061 — Restore last-used target template from settings.
        rangePicker.restoreFromTemplate(settings.lastUsedPreset.target)
        rangePicker.refreshDisplays()
    }

    // MARK: Public commands

    /// Test-friendly hook so unit tests can drive state without firing
    /// real ScreenCaptureKit.
    func applyState(_ new: CaptureState) {
        state = new
        switch new {
        case .saved(let url, let reason):
            savedFileURL = url
            missingPermission = nil
            stopElapsedTimer()
            MenuBarStatusItem.shared.hide()                   // T044
            GlobalHotkey.shared.unregister()
            // T045 — fire 已保存 notification + in-app banner
            Notifier.shared.recordingSaved(fileURL: url)
            Task { [weak self] in
                await Logger.shared.log(.recordingStopped, .info, [
                    "end_reason": reason.rawValue,
                    "file_url": url.path
                ])
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .saved = self?.state { self?.savedFileURL = nil }
            }
        case .errorPermission(let p):
            missingPermission = p
            stopElapsedTimer()
            MenuBarStatusItem.shared.hide()
        case .recording(let started):
            startedAt = started
            startElapsedTimer()
            // T062 — Start monitoring for target disappearance
            if let target = rangePicker.buildTarget() {
                startTargetWatcher(for: target)
            }
            MenuBarStatusItem.shared.showRecording(startedAt: started)
            MenuBarStatusItem.shared.onStopClicked = { [weak self] in
                self?.toggleRecording()
            }
            MenuBarStatusItem.shared.onShowMainWindowClicked = nil
        case .finalizing:
            stopElapsedTimer()
            stopTargetWatcher()
        case .idle:
            savedFileURL = nil
            missingPermission = nil
            stopElapsedTimer()
            MenuBarStatusItem.shared.hide()
        case .interrupted(let reason):
            stopElapsedTimer()
            MenuBarStatusItem.shared.hide()
            GlobalHotkey.shared.unregister()
            Task { await Logger.shared.log(.recordingStopped, .warn, [
                "end_reason": reason.rawValue
            ]) }
        case .errorRuntime(let msg):
            stopElapsedTimer()
            MenuBarStatusItem.shared.hide()
            GlobalHotkey.shared.unregister()
            Task { await Logger.shared.log(.recordingFailed, .error, [
                "phase": "runtime", "error_message": msg
            ]) }
        default:
            break
        }
    }

    func toggleRecording() {
        switch state {
        case .recording, .finalizing:
            Task { await self.coordinator.stop() }
        default:
            Task { await self.startRecording() }
        }
    }

    func showInFinder() {
        guard let url = savedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openMissingPermissionSettings() {
        guard let p = missingPermission else { return }
        switch p {
        case .screenRecording: Permissions.openScreenRecordingSettings()
        case .microphone:      Permissions.openMicrophoneSettings()
        case .notifications:   Permissions.openNotificationSettings()
        }
    }

    func dismissPermissionCard() {
        missingPermission = nil
        applyState(.idle)
    }

    /// Called from "重新检测" — re-runs the preflight check + immediately
    /// retries `startRecording` if the permission has flipped to granted.
    func retryAfterPermissionGrant() {
        let perm = Permissions.screenRecording()
        if perm == .granted {
            missingPermission = nil
            toggleRecording()
        } else {
            // Still denied — keep the card visible; the user will most
            // likely need to fully quit + relaunch the app for ad-hoc
            // builds (the card's disclosure group explains this).
            Task {
                await Logger.shared.log(.permissionCheck, .info, [
                    "permission": "screenRecording",
                    "status": perm.rawValue,
                    "phase": "user_retry"
                ])
            }
        }
    }

    // MARK: Private

    private func startRecording() async {
        // 1. Permission gate (CGPreflight is sync, instant, no dialog).
        if fakePermissionDenied {
            applyState(.errorPermission(missing: .screenRecording))
            return
        }
        var perm = Permissions.screenRecording()
        if perm != .granted {
            // First try the OS-level request — this triggers macOS's native
            // permission dialog (the very first time per cdhash) and *also*
            // adds the app to System Settings → Privacy → Screen Recording
            // so the user has a toggle to flip even if they dismiss it.
            await Logger.shared.log(.permissionCheck, .info, [
                "permission": "screenRecording",
                "status": perm.rawValue,
                "phase": "preflight_failed_will_request"
            ])
            _ = Permissions.requestScreenRecording()
            // Re-check after the request — TCC sometimes flips immediately
            // (e.g. user already granted previously and macOS just needed to
            // be prodded), but more often a relaunch is required.
            try? await Task.sleep(nanoseconds: 300_000_000)
            perm = Permissions.screenRecording()
        }
        if perm != .granted {
            applyState(.errorPermission(missing: .screenRecording))
            await Logger.shared.log(.permissionCheck, .info, [
                "permission": "screenRecording",
                "status": perm.rawValue,
                "phase": "after_request"
            ])
            return
        }

        // 2. Build StartRequest from current preset + settings.
        //    T061 — Persist the chosen target template before starting.
        let template = rangePicker.buildTemplate()
        settings.updateLastUsedPreset { p in p.target = template }
        let preset = settings.lastUsedPreset
        let saveDir = settings.settings.saveDirectory(for: preset.mode)
        let id = UUID()
        let fileURL = RecordingFileNamer.makeFileURL(
            in: saveDir, at: Date(), format: preset.videoConfig.container
        )
        let target: RecordingTarget = rangePicker.buildTarget()
            ?? .fullScreen(displayID: CGMainDisplayID())

        applyState(.preparing)

        do {
            try await coordinator.start(.init(
                recordingID: id,
                mode: preset.mode,
                target: target,
                audioSources: preset.audioSources,
                videoConfig: preset.videoConfig,
                containerFormat: preset.videoConfig.container,
                saveDirectoryURL: saveDir,
                finalFileURL: fileURL,
                preset: preset
            ))
        } catch {
            applyState(.errorRuntime(message: error.localizedDescription))
            await Logger.shared.log(.recordingFailed, .error, [
                "phase": "start",
                "error_message": error.localizedDescription
            ])
            return
        }

        // 3. Register global hotkey (best-effort; failure is FR-029)
        let registration = GlobalHotkey.shared.register { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        switch registration {
        case .registered:
            hotkeyAvailable = true
            await Logger.shared.log(.hotkeyRegisterOK, .info, ["key": "ctrl+shift+k"])
        case .conflict, .failed:
            hotkeyAvailable = false
            Notifier.shared.hotkeyUnavailable()
            await Logger.shared.log(.hotkeyRegisterFail, .warn, ["key": "ctrl+shift+k"])
        }
    }

    // MARK: Target watcher (T062)

    /// Start monitoring for window/display disappearance during recording.
    private func startTargetWatcher(for target: RecordingTarget) {
        stopTargetWatcher()

        switch target {
        case .window(let snap):
            // Poll every 500ms for window existence
            targetWatcherTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    let still = self?.isWindowStillPresent(snap.windowID) ?? true
                    if !still {
                        await Logger.shared.log(.targetWindowLost, .warn, [
                            "window_id": Int(snap.windowID),
                            "window_title": snap.windowTitle
                        ])
                        await self?.coordinator.stopWithReason(.targetGone)
                        return
                    }
                }
            }

        case .fullScreen(let displayID):
            // Watch for display removal via notification
            displayChangeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if !self.isDisplayStillPresent(displayID) {
                    Task {
                        await Logger.shared.log(.targetWindowLost, .warn, [
                            "display_id": Int(displayID)
                        ])
                        await self.coordinator.stopWithReason(.targetGone)
                    }
                }
            }

        case .region:
            // Region doesn't disappear, but the display it's on might
            break
        }
    }

    private func stopTargetWatcher() {
        targetWatcherTask?.cancel()
        targetWatcherTask = nil
        if let obs = displayChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            displayChangeObserver = nil
        }
    }

    private nonisolated func isWindowStillPresent(_ windowID: CGWindowID) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { ($0[kCGWindowNumber as String] as? Int) == Int(windowID) }
    }

    private nonisolated func isDisplayStillPresent(_ displayID: CGDirectDisplayID) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).contains(displayID)
    }

    // MARK: Timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        updateElapsed()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateElapsed() }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsed() {
        guard let started = startedAt else { return }
        let secs = Int(Date().timeIntervalSince(started))
        let mm = secs / 60
        let ss = secs % 60
        elapsedDescription = String(format: "%02d:%02d", mm, ss)
    }
}

// MARK: - Bridge: let CaptureCoordinator publish state changes

extension CaptureCoordinator {
    func setOnStateChange(_ cb: @escaping @Sendable (CaptureState) -> Void) {
        self.onStateChange = cb
    }
}
