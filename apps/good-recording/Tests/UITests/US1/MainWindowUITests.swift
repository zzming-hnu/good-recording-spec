// good-recording — Tests/UITests/US1/MainWindowUITests.swift (T036)
//
// XCUITest smoke for US1's happy path. Asserts the primary button label
// flips between "开始录制" / "停止录制" and that "已保存" eventually appears.
//
// Requires TCC pre-authorization (Screen Recording).

import XCTest

@MainActor
final class MainWindowUITests: XCTestCase {

    func testHappyPathRecordSave() throws {
        let app = XCUIApplication()
        app.launchEnvironment["GOOD_RECORDING_UI_TEST"] = "1"
        app.launch()

        let startButton = app.buttons["开始录制"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Could not find 开始录制 button")
        startButton.click()

        // Either the recording starts (label flips) OR the permission card
        // appears. We accept the first, fail the second on this gating run.
        let stopButton = app.buttons["停止录制"]
        let permissionCard = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '需要您的允许'")
        ).firstMatch

        let appeared = stopButton.waitForExistence(timeout: 8)
        if !appeared, permissionCard.exists {
            throw XCTSkip("Screen Recording permission not granted on this runner.")
        }
        XCTAssertTrue(appeared, "Did not transition to recording state")

        // Record briefly then stop.
        sleep(2)
        stopButton.click()

        let savedBanner = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '已保存'")
        ).firstMatch
        XCTAssertTrue(savedBanner.waitForExistence(timeout: 8),
                      "Did not see '已保存' banner within 8s")
    }
}
