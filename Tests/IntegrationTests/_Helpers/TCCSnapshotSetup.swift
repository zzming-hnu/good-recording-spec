// good-recording — Tests/IntegrationTests/_Helpers/TCCSnapshotSetup.swift (T027)
//
// Asserts the integration-test runner is in a TCC-pre-authorized environment
// (Screen Recording + Microphone + Notifications all granted) and skips the
// test cleanly with a diagnostic message otherwise. Eliminates the most
// common false-positive in integration runs.
//
// Source: home-spec/specs/001-good-recording/quickstart.md §5

import XCTest
import AVFoundation
import ScreenCaptureKit
import UserNotifications

public enum TCCSnapshotSetup {

    /// Call this at the top of every IntegrationTests test method.
    /// Throws an `XCTSkip` with a helpful message if any required permission
    /// is missing.
    public static func requireFullAuthorization(
        screenRecording: Bool = true,
        microphone: Bool = true,
        notifications: Bool = false,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        if screenRecording {
            do {
                _ = try await SCShareableContent.current
            } catch {
                throw XCTSkip(
                    "Screen Recording permission missing. Add good-recording.app's test runner " +
                    "to System Settings → Privacy & Security → Screen Recording, then re-run."
                )
            }
        }

        if microphone {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: break
            default:
                throw XCTSkip(
                    "Microphone permission missing. Add good-recording.app's test runner to " +
                    "System Settings → Privacy & Security → Microphone, then re-run."
                )
            }
        }

        if notifications {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: break
            default:
                throw XCTSkip(
                    "Notifications permission missing. Add good-recording.app's test runner to " +
                    "System Settings → Notifications, then re-run."
                )
            }
        }
    }

    /// A throwaway directory under `tmp/` for integration-test recording files.
    /// Created fresh per call; caller is responsible for cleanup.
    public static func makeTempRecordingDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("good-recording-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
