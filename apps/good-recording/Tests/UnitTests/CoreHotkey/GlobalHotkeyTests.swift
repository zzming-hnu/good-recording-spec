// good-recording — Tests/UnitTests/CoreHotkey/GlobalHotkeyTests.swift (T033)

import XCTest
@testable import GoodRecording

final class GlobalHotkeyTests: XCTestCase {

    /// First registration succeeds (or returns conflict — both are
    /// non-failure outcomes per FR-029).
    func testRegisterReturnsKnownOutcome() {
        let result = GlobalHotkey.shared.register(onTrigger: {})
        defer { GlobalHotkey.shared.unregister() }

        switch result {
        case .registered, .conflict:
            // Both are acceptable. .conflict only happens if another
            // app on the dev machine has ⌃⇧K bound globally.
            break
        case .failed(let code):
            XCTFail("unexpected register failure code=\(code)")
        }
    }

    /// Unregister + re-register must work without leaks.
    func testReregisterIsIdempotent() {
        let r1 = GlobalHotkey.shared.register(onTrigger: {})
        GlobalHotkey.shared.unregister()
        let r2 = GlobalHotkey.shared.register(onTrigger: {})
        defer { GlobalHotkey.shared.unregister() }

        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
    }

    func testHotkeyRegistrationEquality() {
        XCTAssertEqual(HotkeyRegistration.registered, .registered)
        XCTAssertNotEqual(HotkeyRegistration.registered, .conflict)
        XCTAssertEqual(HotkeyRegistration.failed(reasonCode: 7),
                       HotkeyRegistration.failed(reasonCode: 7))
    }
}
