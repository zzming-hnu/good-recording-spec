// good-recording — Tests/UnitTests/FeaturesUS2/WindowPickerViewModelTests.swift (T049)
//
// Validates WindowPickerViewModel filter/search behavior.
// Contract: contracts/ui-surfaces.md S5 — search field filters incrementally.

import XCTest
@testable import GoodRecording

@MainActor
final class WindowPickerViewModelTests: XCTestCase {

    private func makeSampleWindows() -> [WindowSnapshot] {
        [
            WindowSnapshot(windowID: 1, appBundleID: "com.apple.Safari", windowTitle: "Apple - Safari"),
            WindowSnapshot(windowID: 2, appBundleID: "com.apple.finder", windowTitle: "文稿"),
            WindowSnapshot(windowID: 3, appBundleID: "com.apple.Terminal", windowTitle: "zsh — 80×24"),
            WindowSnapshot(windowID: 4, appBundleID: "com.microsoft.VSCode", windowTitle: "project — Visual Studio Code"),
            WindowSnapshot(windowID: 5, appBundleID: "com.apple.Safari", windowTitle: "Google - Safari"),
        ]
    }

    func testInitialStateShowsAllWindows() {
        let vm = WindowPickerViewModel()
        vm.allWindows = makeSampleWindows()
        vm.searchText = ""
        XCTAssertEqual(vm.filteredWindows.count, 5)
    }

    func testSearchFiltersByTitle() {
        let vm = WindowPickerViewModel()
        vm.allWindows = makeSampleWindows()
        vm.searchText = "Safari"
        XCTAssertEqual(vm.filteredWindows.count, 2)
        XCTAssertTrue(vm.filteredWindows.allSatisfy { $0.windowTitle.contains("Safari") })
    }

    func testSearchFiltersByBundleID() {
        let vm = WindowPickerViewModel()
        vm.allWindows = makeSampleWindows()
        vm.searchText = "Terminal"
        XCTAssertEqual(vm.filteredWindows.count, 1)
        XCTAssertEqual(vm.filteredWindows.first?.windowID, 3)
    }

    func testSearchIsCaseInsensitive() {
        let vm = WindowPickerViewModel()
        vm.allWindows = makeSampleWindows()
        vm.searchText = "safari"
        XCTAssertEqual(vm.filteredWindows.count, 2,
                       "Search must be case-insensitive")
    }

    func testEmptySearchShowsAll() {
        let vm = WindowPickerViewModel()
        vm.allWindows = makeSampleWindows()
        vm.searchText = "something that matches nothing"
        XCTAssertEqual(vm.filteredWindows.count, 0)
        vm.searchText = ""
        XCTAssertEqual(vm.filteredWindows.count, 5)
    }

    func testEmptyWindowListShowsEmptyState() {
        let vm = WindowPickerViewModel()
        vm.allWindows = []
        XCTAssertTrue(vm.filteredWindows.isEmpty)
        XCTAssertTrue(vm.showsEmptyState)
    }

    func testSelectWindowDismisses() {
        let vm = WindowPickerViewModel()
        vm.allWindows = makeSampleWindows()
        var didDismiss = false
        vm.onSelect = { _ in didDismiss = true }
        vm.selectWindow(vm.allWindows[0])
        XCTAssertTrue(didDismiss, "Selecting a window must dismiss the picker (S5)")
    }
}
