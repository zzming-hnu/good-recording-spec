// good-recording — Core/Capture/MicrophoneCapture.swift (T023)
//
// AVCaptureSession-based microphone capture. Forwards CMSampleBuffers to a
// callback; reports route changes (device unplug) so the recording stays
// alive (FR-012, US3 AC3).
//
// Concurrency: CMSampleBuffer is non-Sendable, so we keep the sample-buffer
// callback strictly inside the SampleProxy's nonisolated context (no actor
// hops). Lifecycle methods (start/stop) remain actor-isolated.
//
// Source of truth: home-spec/specs/001-good-recording/research.md R2

import Foundation
import AVFoundation
@preconcurrency import CoreMedia

public actor MicrophoneCapture {

    public enum CaptureError: Error, Sendable {
        case noInputDevice
        case sessionConfigFailed
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "good.recording.mic.capture", qos: .userInitiated)
    private var sampleProxy: SampleProxy?
    private var observerToken: NSObjectProtocol?

    public init() {}

    /// Start microphone capture using the system's default audio input device.
    public func start(
        onSample: @escaping @Sendable (CMSampleBuffer) -> Void,
        onRouteChange: @escaping @Sendable () -> Void
    ) throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CaptureError.noInputDevice
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.sessionConfigFailed
        }

        session.beginConfiguration()
        if !session.inputs.contains(where: { $0 === input }), session.canAddInput(input) {
            session.addInput(input)
        }

        let proxy = SampleProxy(handler: onSample)
        sampleProxy = proxy
        output.setSampleBufferDelegate(proxy, queue: queue)
        if !session.outputs.contains(where: { $0 === output }), session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        observerToken = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { _ in onRouteChange() }

        session.startRunning()
    }

    public func stop() {
        session.stopRunning()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        sampleProxy = nil
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
    }
}

// MARK: - Bridging proxy

private final class SampleProxy: NSObject,
                                  AVCaptureAudioDataOutputSampleBufferDelegate,
                                  @unchecked Sendable {
    private let handler: @Sendable (CMSampleBuffer) -> Void

    init(handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }
}
