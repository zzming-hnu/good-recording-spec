// good-recording — Tests/IntegrationTests/US1/RecordingFlowTests.swift
// (T034 testOneClickRecordSave + T035 testStopViaHotkey)
//
// Exercises the full capture pipeline against real ScreenCaptureKit.
// Requires a TCC-authorized runner (Screen Recording + Microphone).
// Auto-skips on unauthorized runners via TCCSnapshotSetup.

import XCTest
import AVFoundation
@testable import GoodRecording

final class RecordingFlowTests: XCTestCase {

    // MARK: T034 — US1 Independent Test

    func testOneClickRecordSave() async throws {
        try await TCCSnapshotSetup.requireFullAuthorization(
            screenRecording: true, microphone: false
        )

        let dir = try TCCSnapshotSetup.makeTempRecordingDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = UUID()
        let fileURL = RecordingFileNamer.makeFileURL(
            in: dir, at: Date(), format: .mp4
        )

        let coord = CaptureCoordinator()
        try await coord.start(.init(
            recordingID: id,
            mode: .video,
            target: .fullScreen(displayID: CGMainDisplayID()),
            audioSources: .allOff,
            videoConfig: .default,
            containerFormat: .mp4,
            saveDirectoryURL: dir,
            finalFileURL: fileURL,
            preset: .factoryDefault
        ))

        // Record for ~3 seconds (shorter than the 10s mentioned in spec.md
        // Independent Test, but enough to validate the full path).
        try await Task.sleep(nanoseconds: 3_000_000_000)

        await coord.stop()

        // Wait for finalize state
        for _ in 0..<50 {   // up to 5 s
            let s = await coord.state
            if case .saved = s { break }
            if case .errorRuntime(let msg) = s { XCTFail("runtime error: \(msg)"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let final = await coord.state
        guard case .saved(let savedURL, _) = final else {
            XCTFail("did not reach .saved, got \(final)"); return
        }

        // Verify the file is actually playable.
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: savedURL.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)

        let asset = AVURLAsset(url: savedURL)
        let dur = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(dur, 1.0)
        let tracks = try await asset.load(.tracks)
        XCTAssertGreaterThan(tracks.count, 0)
    }

    // MARK: T035 — Stop via global hotkey

    func testStopViaHotkey() async throws {
        try await TCCSnapshotSetup.requireFullAuthorization(
            screenRecording: true, microphone: false
        )

        let dir = try TCCSnapshotSetup.makeTempRecordingDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let coord = CaptureCoordinator()
        try await coord.start(.init(
            mode: .video,
            target: .fullScreen(displayID: CGMainDisplayID()),
            audioSources: .allOff,
            videoConfig: .default,
            containerFormat: .mp4,
            saveDirectoryURL: dir,
            finalFileURL: RecordingFileNamer.makeFileURL(in: dir, at: Date(), format: .mp4),
            preset: .factoryDefault
        ))

        // Wire ⌃⇧K to call coord.stop()
        let registration = GlobalHotkey.shared.register {
            Task { await coord.stop() }
        }
        defer { GlobalHotkey.shared.unregister() }

        if case .conflict = registration {
            throw XCTSkip("⌃⇧K is held by another app on this runner; skip.")
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Synthesize ⌃⇧K — Carbon hotkey listens to system events; we use
        // CGEventPost to inject one.
        postCtrlShiftK()

        for _ in 0..<50 {
            let s = await coord.state
            if case .saved = s { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let final = await coord.state
        if case .saved = final { /* good */ } else {
            XCTFail("hotkey did not stop recording: \(final)")
        }
    }

    // MARK: helpers

    private func postCtrlShiftK() {
        let src = CGEventSource(stateID: .hidSystemState)
        let kVK_K: CGKeyCode = 0x28
        let down = CGEvent(keyboardEventSource: src, virtualKey: kVK_K, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: kVK_K, keyDown: false)
        let mods: CGEventFlags = [.maskControl, .maskShift]
        down?.flags = mods
        up?.flags = mods
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
