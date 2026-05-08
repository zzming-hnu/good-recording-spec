// good-recording — Tests/UnitTests/CoreCapture/CaptureCoordinatorTests.swift (T031)
//
// Verifies CaptureCoordinator's state machine transitions per data-model.md E1.
// Stops short of touching real ScreenCaptureKit (which needs TCC) — those
// integration scenarios live in Tests/IntegrationTests/US1/.

import XCTest
@testable import GoodRecording

final class CaptureCoordinatorTests: XCTestCase {

    func testInitialStateIsIdle() async {
        let coord = CaptureCoordinator(logger: .shared)
        let state = await coord.state
        XCTAssertEqual(state, .idle)
    }

    func testStopWhenNotRecordingIsNoop() async {
        let coord = CaptureCoordinator(logger: .shared)
        await coord.stop()
        let state = await coord.state
        XCTAssertEqual(state, .idle, "stop on idle should be a no-op")
    }

    func testEndReasonClassification() {
        XCTAssertTrue(EndReason.userStop.isNormal)
        XCTAssertFalse(EndReason.diskFull.isNormal)
        XCTAssertFalse(EndReason.targetGone.isNormal)
        XCTAssertFalse(EndReason.systemSignal.isNormal)
        XCTAssertFalse(EndReason.crashed.isNormal)

        XCTAssertTrue(EndReason.userStop.requiresNotification)
        XCTAssertTrue(EndReason.diskFull.requiresNotification)
        XCTAssertFalse(EndReason.crashed.requiresNotification)
    }

    func testRecordingDurationFromStartToEnd() {
        let start = Date(timeIntervalSince1970: 1_810_000_000)
        let end   = Date(timeIntervalSince1970: 1_810_000_010)   // +10s
        let r = Recording(
            mode: .video,
            startedAt: start,
            endedAt: end,
            target: .fullScreen(displayID: 1),
            audioSources: .micOnly,
            videoConfig: .default,
            containerFormat: .mp4,
            fileURL: URL(fileURLWithPath: "/tmp/x.mp4"),
            presetUsed: .factoryDefault
        )
        XCTAssertEqual(r.duration, 10.0, accuracy: 0.001)
    }

    func testRecordingAbnormalEndDetection() {
        let baseStartedAt = Date()
        let baseURL = URL(fileURLWithPath: "/tmp/x.mp4")

        let normal = Recording(
            mode: .video, startedAt: baseStartedAt,
            endedAt: Date(), target: nil,
            audioSources: .allOff, videoConfig: nil,
            containerFormat: .m4a, fileURL: baseURL,
            endReason: .userStop, presetUsed: .factoryDefault
        )
        XCTAssertFalse(normal.wasAbnormalEnd)

        let crashed = Recording(
            mode: .video, startedAt: baseStartedAt,
            endedAt: Date(), target: nil,
            audioSources: .allOff, videoConfig: nil,
            containerFormat: .m4a, fileURL: baseURL,
            endReason: .crashed, presetUsed: .factoryDefault
        )
        XCTAssertTrue(crashed.wasAbnormalEnd)
    }
}
