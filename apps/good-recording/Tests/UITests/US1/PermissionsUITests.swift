// good-recording — Tests/UITests/US1/PermissionsUITests.swift (T037)
//
// XCUITest for spec.md US1 AC3 — clicking 开始录制 without Screen Recording
// permission MUST surface the permission card with "打开系统设置" deeplink,
// not crash, and not start recording.
//
// To exercise the denied path on a runner that has the permission granted,
// pass GOOD_RECORDING_FAKE_PERMISSION_DENIED=1 in launchEnvironment.

import XCTest

@MainActor
final class PermissionsUITests: XCTestCase {

    func testScreenRecordingDeniedShowsCard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["GOOD_RECORDING_UI_TEST"] = "1"
        app.launchEnvironment["GOOD_RECORDING_FAKE_PERMISSION_DENIED"] = "1"
        app.launch()

        let startButton = app.buttons["开始录制"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.click()

        let card = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '需要您的允许'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 4),
                      "Permission card did not appear")

        // 打开系统设置 button should be reachable.
        let openSettings = app.buttons["打开系统设置"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 2))

        // App must NOT be in recording state.
        let stopButton = app.buttons["停止录制"]
        XCTAssertFalse(stopButton.exists, "App entered recording state despite denied permission")
    }
}
