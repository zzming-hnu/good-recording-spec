// good-recording — Tests/UnitTests/FeaturesUS2/RangePickerViewModelTests.swift (T048)
//
// Validates RangePickerViewModel state preservation across segment switches.
// Contract: contracts/ui-surfaces.md S2 — switching segments MUST NOT lose
// the previously-selected sub-value.

import XCTest
@testable import GoodRecording

@MainActor
final class RangePickerViewModelTests: XCTestCase {

    func testInitialSegmentIsFullScreen() {
        let vm = RangePickerViewModel()
        XCTAssertEqual(vm.selectedSegment, .fullScreen)
    }

    func testSwitchToWindowPreservesFullScreenDisplay() {
        let vm = RangePickerViewModel()
        // Simulate user picking a specific display in fullScreen mode
        let secondaryDisplayID: UInt32 = 42
        vm.selectDisplay(secondaryDisplayID)
        XCTAssertEqual(vm.selectedDisplayID, secondaryDisplayID)

        // Switch to window mode
        vm.selectedSegment = .window
        XCTAssertEqual(vm.selectedSegment, .window)

        // Switch back to fullScreen — the previous display selection survives
        vm.selectedSegment = .fullScreen
        XCTAssertEqual(vm.selectedDisplayID, secondaryDisplayID,
                       "Display selection must survive segment switch (S2 contract)")
    }

    func testSwitchToRegionPreservesWindowSelection() {
        let vm = RangePickerViewModel()
        let snap = WindowSnapshot(windowID: 123, appBundleID: "com.apple.Safari", windowTitle: "Safari")
        vm.selectedSegment = .window
        vm.selectWindow(snap)
        XCTAssertEqual(vm.selectedWindow, snap)

        // Switch to region → back to window
        vm.selectedSegment = .region
        vm.selectedSegment = .window
        XCTAssertEqual(vm.selectedWindow, snap,
                       "Window selection must survive segment switch (S2 contract)")
    }

    func testRegionRectPreservedAcrossSwitches() {
        let vm = RangePickerViewModel()
        let rect = CGRect(x: 100, y: 100, width: 800, height: 600)
        vm.selectedSegment = .region
        vm.selectRegion(rect)
        XCTAssertEqual(vm.selectedRegion, rect)

        // Switch away and back
        vm.selectedSegment = .fullScreen
        vm.selectedSegment = .region
        XCTAssertEqual(vm.selectedRegion, rect,
                       "Region rect must survive segment switch (S2 contract)")
    }

    func testBuildTargetFullScreen() {
        let vm = RangePickerViewModel()
        vm.selectedSegment = .fullScreen
        let target = vm.buildTarget()
        if case .fullScreen = target {
            // expected
        } else {
            XCTFail("Expected .fullScreen target, got \(String(describing: target))")
        }
    }

    func testBuildTargetWindow() {
        let vm = RangePickerViewModel()
        let snap = WindowSnapshot(windowID: 99, appBundleID: "com.test", windowTitle: "Test")
        vm.selectedSegment = .window
        vm.selectWindow(snap)
        let target = vm.buildTarget()
        if case .window(let s) = target {
            XCTAssertEqual(s, snap)
        } else {
            XCTFail("Expected .window target, got \(String(describing: target))")
        }
    }

    func testBuildTargetRegion() {
        let vm = RangePickerViewModel()
        let rect = CGRect(x: 50, y: 50, width: 640, height: 480)
        vm.selectedSegment = .region
        vm.selectRegion(rect)
        let target = vm.buildTarget()
        if case .region(let r) = target {
            XCTAssertEqual(r, rect)
        } else {
            XCTFail("Expected .region target, got \(String(describing: target))")
        }
    }

    func testBuildTargetWindowWithoutSelectionReturnsNil() {
        let vm = RangePickerViewModel()
        vm.selectedSegment = .window
        // No window selected yet
        let target = vm.buildTarget()
        XCTAssertNil(target, "Window mode without selection should return nil")
    }

    func testSegmentCasesMatchSpec() {
        let allCases = RangePickerSegment.allCases
        XCTAssertEqual(allCases.count, 3, "S2 defines exactly 3 segments")
        XCTAssertTrue(allCases.contains(.fullScreen))
        XCTAssertTrue(allCases.contains(.window))
        XCTAssertTrue(allCases.contains(.region))
    }
}
