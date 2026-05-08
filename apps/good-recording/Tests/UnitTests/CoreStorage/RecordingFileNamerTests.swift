// good-recording — Tests/UnitTests/CoreStorage/RecordingFileNamerTests.swift (T030)
//
// Verifies file naming + collision handling per
// home-spec/specs/001-good-recording/contracts/output-files.md

import XCTest
@testable import GoodRecording

final class RecordingFileNamerTests: XCTestCase {

    // MARK: baseName

    func testBaseNameMatchesContract() {
        let date = Date(timeIntervalSince1970: 1_810_000_000)   // 2027-05-08 …
        let name = RecordingFileNamer.baseName(at: date)
        XCTAssertTrue(name.hasPrefix("Recording "), "got: \(name)")
        // Format: "Recording yyyy-MM-dd HH.mm.ss"  → 19 + 1 + len("Recording ")
        // but timezone-dependent; just sanity-check structure.
        let parts = name.dropFirst("Recording ".count).split(separator: " ")
        XCTAssertEqual(parts.count, 2, "expected date + time")
    }

    func testBaseNameUsesPeriodSeparators() {
        // ":" is forbidden in HFS+/APFS-via-UI on some legacy paths;
        // contract requires "." as the time separator.
        let name = RecordingFileNamer.baseName(at: Date())
        XCTAssertFalse(name.contains(":"), "filename must not contain ':'")
    }

    // MARK: collision handling

    func testFirstFileNoCollision() {
        let stub = StubClock(existing: [])
        let url = RecordingFileNamer.makeFileURL(
            in: URL(fileURLWithPath: "/tmp"),
            at: Date(),
            format: .mp4,
            clock: stub
        )
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertFalse(url.lastPathComponent.contains("("))
    }

    func testCollisionAppendsTwo() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let baseName = RecordingFileNamer.baseName(at: date)
        let dir = URL(fileURLWithPath: "/tmp")
        let stub = StubClock(existing: [
            dir.appendingPathComponent("\(baseName).mp4").path
        ])
        let url = RecordingFileNamer.makeFileURL(in: dir, at: date, format: .mp4, clock: stub)
        XCTAssertTrue(url.lastPathComponent.contains(" (2)"), "got: \(url.lastPathComponent)")
    }

    func testCollisionWalksUntilFree() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let baseName = RecordingFileNamer.baseName(at: date)
        let dir = URL(fileURLWithPath: "/tmp")
        let existing: Set<String> = [
            dir.appendingPathComponent("\(baseName).mp4").path,
            dir.appendingPathComponent("\(baseName) (2).mp4").path,
            dir.appendingPathComponent("\(baseName) (3).mp4").path
        ]
        let stub = StubClock(existing: existing)
        let url = RecordingFileNamer.makeFileURL(in: dir, at: date, format: .mp4, clock: stub)
        XCTAssertTrue(url.lastPathComponent.contains(" (4)"), "got: \(url.lastPathComponent)")
    }

    // MARK: temp file

    func testTempFileURLIsPartial() {
        let id = UUID()
        let tmp = RecordingFileNamer.tempFileURL(
            in: FileManager.default.temporaryDirectory,
            recordingID: id,
            format: .mov
        )
        XCTAssertTrue(tmp.lastPathComponent.hasSuffix(".mov.partial"))
        XCTAssertTrue(tmp.lastPathComponent.contains(id.uuidString))
    }

    // MARK: container ext

    func testEachContainerHasMatchingExtension() {
        XCTAssertEqual(ContainerFormat.mp4.fileExtension, "mp4")
        XCTAssertEqual(ContainerFormat.mov.fileExtension, "mov")
        XCTAssertEqual(ContainerFormat.m4a.fileExtension, "m4a")
    }
}

// MARK: - Stub clock for hermetic testing

private struct StubClock: Clock {
    let existing: Set<String>

    init(existing: Set<String>) { self.existing = existing }
    init(existing: [String]) { self.init(existing: Set(existing)) }

    func fileExists(at url: URL) -> Bool { existing.contains(url.path) }
}
