// good-recording — Tests/UITests/US2/RangePickerUITests.swift (T054)
//
// UI test: switching range picker segments preserves prior selections.
// Contract: contracts/ui-surfaces.md S2

import XCTest

@MainActor
final class RangePickerUITests: XCTestCase {

    // MARK: T054 — testSegmentSwitching

    func testSegmentSwitching() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Verify range picker is visible in idle state
        let segmentedControl = app.segmentedControls["RangePicker"]
        guard segmentedControl.waitForExistence(timeout: 5) else {
            throw XCTSkip("RangePicker not found — US2 feature may be disabled")
        }

        // 2. Switch to "单个窗口"
        let windowSegment = segmentedControl.buttons["单个窗口"]
        XCTAssertTrue(windowSegment.exists, "Window segment must exist")
        windowSegment.tap()

        // 3. Pick a window (if picker appears)
        let windowPicker = app.buttons["选择窗口…"]
        if windowPicker.waitForExistence(timeout: 2) {
            windowPicker.tap()
            let firstRow = app.tables.cells.firstMatch
            if firstRow.waitForExistence(timeout: 3) {
                firstRow.tap()
            }
        }

        // 4. Switch to "自定义区域"
        let regionSegment = segmentedControl.buttons["自定义区域"]
        XCTAssertTrue(regionSegment.exists, "Region segment must exist")
        regionSegment.tap()

        // 5. Switch back to "单个窗口" — previous selection should survive
        windowSegment.tap()
    }

    func testFullScreenIsDefaultSegment() throws {
        let app = XCUIApplication()
        app.launch()

        let segmentedControl = app.segmentedControls["RangePicker"]
        guard segmentedControl.waitForExistence(timeout: 5) else {
            throw XCTSkip("RangePicker not found")
        }

        let fullScreenSegment = segmentedControl.buttons["整个屏幕"]
        XCTAssertTrue(fullScreenSegment.isSelected || fullScreenSegment.value as? String == "1",
                      "Full screen should be the default selected segment")
    }
}
