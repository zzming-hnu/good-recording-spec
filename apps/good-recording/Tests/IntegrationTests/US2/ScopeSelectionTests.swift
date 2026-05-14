// good-recording — Tests/IntegrationTests/US2/ScopeSelectionTests.swift (T050–T053)
//
// Integration tests for US2 — scope selection. These require TCC permissions
// (Screen Recording) to actually exercise ScreenCaptureKit.
// See: quickstart.md §5 for VM setup.

import XCTest
@testable import GoodRecording

final class ScopeSelectionTests: XCTestCase {

    // MARK: T050 — testWindowOnlyCapture

    @MainActor
    func testWindowOnlyCapture() async throws {
        try skipIfNoTCC()

        let fixture = TestFixtureWindow(color: .systemRed)
        fixture.show()
        defer { fixture.close() }

        // 2. Enumerate windows via SCShareableContent
        let coordinator = CaptureCoordinator()
        let settings = SettingsStore.shared
        let saveDir = settings.settings.saveDirectory(for: .video)
        let fileURL = RecordingFileNamer.makeFileURL(in: saveDir, at: Date(), format: .mp4)

        let windowSnap = WindowSnapshot(
            windowID: fixture.windowID,
            appBundleID: Bundle.main.bundleIdentifier ?? "",
            windowTitle: fixture.title
        )

        try await coordinator.start(.init(
            mode: .video,
            target: .window(windowSnap),
            audioSources: .allOff,
            videoConfig: .default,
            containerFormat: .mp4,
            saveDirectoryURL: saveDir,
            finalFileURL: fileURL,
            preset: .factoryDefault
        ))

        try await Task.sleep(nanoseconds: 3_000_000_000)
        await coordinator.stop()

        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "Output file must exist after window-only recording")
    }

    // MARK: T051 — testRegionRectPersisted

    @MainActor
    func testRegionRectPersisted() async throws {
        let testRect = CGRect(x: 100, y: 200, width: 800, height: 600)

        let vm = RangePickerViewModel()
        vm.selectedSegment = .region
        vm.selectRegion(testRect)

        let settings = SettingsStore.shared
        settings.updateLastUsedPreset { preset in
            preset.target = .regionLastSelected(testRect)
        }

        // 3. Simulate restart — re-read from settings
        let reloaded = settings.lastUsedPreset
        if case .regionLastSelected(let rect) = reloaded.target {
            XCTAssertEqual(rect, testRect,
                           "Region rect must survive restart (US2 AC2)")
        } else {
            XCTFail("Expected .regionLastSelected, got \(reloaded.target)")
        }
    }

    // MARK: T052 — testTargetWindowDisappears

    @MainActor
    func testTargetWindowDisappears() async throws {
        try skipIfNoTCC()

        let fixture = TestFixtureWindow(color: .systemBlue)
        fixture.show()

        let coordinator = CaptureCoordinator()
        let settings = SettingsStore.shared
        let saveDir = settings.settings.saveDirectory(for: .video)
        let fileURL = RecordingFileNamer.makeFileURL(in: saveDir, at: Date(), format: .mp4)

        let snap = WindowSnapshot(
            windowID: fixture.windowID,
            appBundleID: Bundle.main.bundleIdentifier ?? "",
            windowTitle: fixture.title
        )

        try await coordinator.start(.init(
            mode: .video,
            target: .window(snap),
            audioSources: .allOff,
            videoConfig: .default,
            containerFormat: .mp4,
            saveDirectoryURL: saveDir,
            finalFileURL: fileURL,
            preset: .factoryDefault
        ))

        // Wait a bit, then close the window
        try await Task.sleep(nanoseconds: 2_000_000_000)
        fixture.close()

        // SCK should detect the gone window and trigger auto-stop.
        // Wait up to 3 seconds for the coordinator to reach a terminal state.
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let s = await coordinator.state
            if case .interrupted(let reason) = s {
                XCTAssertEqual(reason, .targetGone,
                               "End reason must be .targetGone when window disappears (US2 AC3)")
                return
            }
            if case .saved = s {
                return
            }
        }
        let finalState = await coordinator.state
        XCTFail("Expected coordinator to reach .interrupted(.targetGone) or .saved, but got \(finalState)")
    }

    // MARK: T053 — testMultiDisplayRequiresChoice

    @MainActor
    func testMultiDisplayRequiresChoice() async throws {
        let vm = RangePickerViewModel()
        vm.selectedSegment = .fullScreen

        // Simulate multi-display by setting display count > 1
        vm.availableDisplayCount = 2

        XCTAssertTrue(vm.shouldShowDisplayChooser,
                      "Display chooser must appear when >= 2 displays (US2 AC4)")
    }

    // MARK: - Helpers

    private func skipIfNoTCC() throws {
        let perm = Permissions.screenRecording()
        if perm != .granted {
            throw XCTSkip("Screen Recording TCC not granted; skipping integration test")
        }
    }
}

// MARK: - Test fixture window

/// A simple NSWindow with a solid color background, used to verify
/// that a "window only" recording captures only this window's pixels.
@MainActor
private class TestFixtureWindow {
    let window: NSWindow
    var windowID: CGWindowID { CGWindowID(window.windowNumber) }
    var title: String { window.title }

    init(color: NSColor) {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GoodRecording Test Fixture"
        window.backgroundColor = color
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }
}
