// good-recording — Tests/UnitTests/FeaturesUS1/RecordingViewModelTests.swift (T032)
//
// Validates RecordingViewModel's user-facing state mapping. The actual
// CaptureCoordinator interaction is covered by IntegrationTests; here we
// verify state transitions, button labels, and disabled-states.

import XCTest
@testable import GoodRecording

@MainActor
final class RecordingViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = RecordingViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.primaryButtonLabel, "开始录制")
        XCTAssertFalse(vm.primaryButtonIsRecording)
        XCTAssertNil(vm.savedFileURL)
    }

    func testTransitionToRecordingChangesButtonLabel() {
        let vm = RecordingViewModel()
        vm.applyState(.recording(startedAt: Date()))
        XCTAssertEqual(vm.primaryButtonLabel, "停止录制")
        XCTAssertTrue(vm.primaryButtonIsRecording)
    }

    func testSavedStateExposesURL() {
        let vm = RecordingViewModel()
        let url = URL(fileURLWithPath: "/tmp/Recording 2026-05-08 10.06.45.mp4")
        vm.applyState(.saved(fileURL: url, endReason: .userStop))
        XCTAssertEqual(vm.savedFileURL, url)
        XCTAssertEqual(vm.primaryButtonLabel, "开始录制")
    }

    func testPermissionErrorStateBlocksStart() {
        let vm = RecordingViewModel()
        vm.applyState(.errorPermission(missing: .screenRecording))
        XCTAssertEqual(vm.missingPermission, .screenRecording)
        XCTAssertEqual(vm.primaryButtonLabel, "开始录制")
    }

    func testElapsedDescription() {
        let vm = RecordingViewModel()
        let start = Date(timeIntervalSinceNow: -65)   // 1:05 ago
        vm.applyState(.recording(startedAt: start))
        let label = vm.elapsedDescription
        XCTAssertTrue(label.contains(":"), "expected MM:SS, got \(label)")
    }
}
