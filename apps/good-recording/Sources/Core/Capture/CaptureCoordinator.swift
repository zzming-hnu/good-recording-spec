// good-recording — Core/Capture/CaptureCoordinator.swift (T022)
//
// THE central capture state machine. Orchestrates:
//   - ScreenCaptureKit (SCStream)         → video + system audio
//   - MicrophoneCapture (AVCaptureSession) → mic audio
//   - AudioMixer                          → single AAC track
//   - AssetWriterPipeline                 → file on disk
//
// Exposes a single state-machine `state` property + start/stop API.
// Maps SCK errors → EndReason.
//
// Source of truth:
//   home-spec/specs/001-good-recording/data-model.md (E1 state machine)
//   home-spec/specs/001-good-recording/research.md R1, R2

import Foundation
import ScreenCaptureKit
import AVFoundation
@preconcurrency import CoreMedia
import CoreVideo

public actor CaptureCoordinator {

    // MARK: Public input

    public struct StartRequest: Sendable {
        public let recordingID: UUID
        public let mode: RecordingMode
        public let target: RecordingTarget?
        public let audioSources: AudioSourceSet
        public let videoConfig: VideoConfig?
        public let containerFormat: ContainerFormat
        public let saveDirectoryURL: URL
        public let finalFileURL: URL
        public let preset: RecordingPreset

        public init(
            recordingID: UUID = UUID(),
            mode: RecordingMode,
            target: RecordingTarget?,
            audioSources: AudioSourceSet,
            videoConfig: VideoConfig?,
            containerFormat: ContainerFormat,
            saveDirectoryURL: URL,
            finalFileURL: URL,
            preset: RecordingPreset
        ) {
            self.recordingID = recordingID
            self.mode = mode
            self.target = target
            self.audioSources = audioSources
            self.videoConfig = videoConfig
            self.containerFormat = containerFormat
            self.saveDirectoryURL = saveDirectoryURL
            self.finalFileURL = finalFileURL
            self.preset = preset
        }
    }

    // MARK: Public state observation

    public private(set) var state: CaptureState = .idle
    public private(set) var inFlight: Recording?

    /// Hook for a single observer (the ViewModel). Reassign as needed.
    public var onStateChange: (@Sendable (CaptureState) -> Void)?

    // MARK: Internals

    private var stream: SCStream?
    private var streamProxy: StreamProxy?
    private var mic: MicrophoneCapture?
    private var mixer: AudioMixer?
    private var pipeline: AssetWriterPipeline?
    private var sourceSize: CGSize = .zero
    private var startedAt: Date?
    private var pixelFrames: Int = 0

    // Allow injection of a Logger (so unit tests can supply a fake; default = shared)
    private let logger: Logger

    public init(logger: Logger = .shared) {
        self.logger = logger
    }

    // MARK: Start

    public func start(_ req: StartRequest) async throws {
        precondition(state == .idle || isFinishedState(state),
                     "CaptureCoordinator.start called while not idle: \(state)")
        transition(.preparing)

        let presetSnap = req.preset
        let recording = Recording(
            id: req.recordingID,
            mode: req.mode,
            startedAt: Date(),
            target: req.target,
            audioSources: req.audioSources,
            videoConfig: req.videoConfig,
            containerFormat: req.containerFormat,
            fileURL: req.finalFileURL,
            presetUsed: presetSnap
        )
        self.inFlight = recording
        self.startedAt = recording.startedAt
        self.pixelFrames = 0

        // 1. Build SCK stream config (video mode only)
        if req.mode == .video {
            try await startScreenCapture(req)
        }

        // 2. Build mic capture if needed
        if req.audioSources.ambient {
            let mic = MicrophoneCapture()
            self.mic = mic
            try await mic.start(
                onSample: { [weak self] buf in
                    let wrapped = SendableSample(buf)
                    Task { await self?.routeMicSample(wrapped) }
                },
                onRouteChange: { [weak self] in
                    Task { await self?.routeMicChanged() }
                }
            )
        }

        // 3. Build mixer
        let mixer = AudioMixer(config: .init(
            micEnabled: req.audioSources.ambient,
            systemEnabled: req.audioSources.system && req.mode == .video
        ))
        self.mixer = mixer
        await mixer.setOutput { [weak self] mixed in
            let wrapped = SendableSample(mixed)
            Task { await self?.routeMixedAudio(wrapped) }
        }

        // 4. Build pipeline
        let pipeline = AssetWriterPipeline(config: .init(
            recordingID: req.recordingID,
            mode: req.mode,
            videoConfig: req.videoConfig,
            audioSources: req.audioSources,
            sourceVideoSize: req.mode == .video ? sourceSize : nil,
            containerFormat: req.containerFormat,
            saveDirectoryURL: req.saveDirectoryURL,
            finalFileURL: req.finalFileURL
        ))
        self.pipeline = pipeline
        try await pipeline.start()

        // 5. Start the SCStream now that the pipeline is ready
        if let stream = self.stream {
            try await stream.startCapture()
        }

        await logger.log(
            .recordingStarted,
            .info,
            [
                "recording_id":      recording.id.uuidString,
                "mode":              req.mode.rawValue,
                "container":         req.containerFormat.rawValue,
                "audio_ambient":     req.audioSources.ambient,
                "audio_system":      req.audioSources.system,
                "started_at":        ISO8601DateFormatter().string(from: recording.startedAt)
            ]
        )

        transition(.recording(startedAt: recording.startedAt))
    }

    private func startScreenCapture(_ req: StartRequest) async throws {
        let content = try await SCShareableContent.current
        let filter: SCContentFilter
        switch req.target ?? .fullScreen(displayID: CGMainDisplayID()) {
        case .fullScreen(let displayID):
            let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first!
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            sourceSize = CGSize(width: display.width, height: display.height)
        case .window(let snap):
            guard let win = content.windows.first(where: { $0.windowID == snap.windowID }) else {
                throw NSError(domain: "good-recording.capture", code: -100,
                              userInfo: [NSLocalizedDescriptionKey: "window gone"])
            }
            filter = SCContentFilter(desktopIndependentWindow: win)
            sourceSize = CGSize(width: win.frame.width, height: win.frame.height)
        case .region(let rect):
            // SCK 没有"区域"，用全屏 + crop。Apple HIG 推荐这条路径。
            let display = content.displays.first!
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            sourceSize = rect.size
        }

        let scConfig = SCStreamConfiguration()
        scConfig.width = Int(sourceSize.width)
        scConfig.height = Int(sourceSize.height)
        scConfig.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        scConfig.queueDepth = 8
        scConfig.pixelFormat = kCVPixelFormatType_32BGRA
        if #available(macOS 13.0, *) {
            scConfig.capturesAudio = req.audioSources.system
            scConfig.excludesCurrentProcessAudio = true
        }

        let stream = SCStream(filter: filter, configuration: scConfig, delegate: nil)
        let proxy = StreamProxy(
            onVideo: { [weak self] sample in
                let wrapped = SendableSample(sample)
                Task { await self?.routeVideoSample(wrapped) }
            },
            onSystemAudio: { [weak self] sample in
                let wrapped = SendableSample(sample)
                Task { await self?.routeSystemAudioSample(wrapped) }
            },
            onError: { [weak self] reason in
                Task { await self?.handleStreamError(reason) }
            }
        )
        try stream.addStreamOutput(proxy, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        if #available(macOS 13.0, *), req.audioSources.system {
            try stream.addStreamOutput(proxy, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        }
        self.stream = stream
        self.streamProxy = proxy
    }

    // MARK: Stop (user-initiated → 100% playable promise, SC-007)

    public func stop() async {
        await finish(reason: .userStop)
    }

    public func stopWithReason(_ reason: EndReason) async {
        await finish(reason: reason)
    }

    private func finish(reason: EndReason) async {
        // Idempotent — repeated stop is a no-op once we've already left .recording.
        guard case .recording = state else { return }
        transition(.finalizing)

        // 1. Tear down sources
        try? await stream?.stopCapture()
        await mic?.stop()
        self.stream = nil
        self.streamProxy = nil

        // 2. Finalize writer
        guard let pipeline = pipeline else {
            transition(.errorRuntime(message: "pipeline missing"))
            return
        }

        let result: (URL, Int64)
        do {
            result = try await pipeline.finishWriting()
        } catch {
            await pipeline.cancel()
            transition(.errorRuntime(message: error.localizedDescription))
            await logger.log(.recordingFailed, .error, [
                "recording_id": (inFlight?.id.uuidString ?? ""),
                "phase": "finalize",
                "error_message": error.localizedDescription
            ])
            self.pipeline = nil
            self.inFlight = nil
            return
        }

        var finished = inFlight ?? Recording(
            id: UUID(),
            mode: .video,
            startedAt: startedAt ?? Date(),
            target: nil,
            audioSources: .allOff,
            videoConfig: nil,
            containerFormat: .mp4,
            fileURL: result.0,
            presetUsed: .factoryDefault
        )
        finished.endedAt = Date()
        finished.endReason = reason
        finished.fileURL = result.0
        finished.fileSizeBytes = result.1

        await logger.log(.recordingStopped, .info, [
            "recording_id":   finished.id.uuidString,
            "end_reason":     reason.rawValue,
            "duration_ms":    Int(finished.duration * 1000),
            "file_url":       finished.fileURL.path,
            "file_size_bytes": finished.fileSizeBytes
        ])

        self.pipeline = nil
        self.inFlight = nil
        self.startedAt = nil

        if reason.isNormal {
            transition(.saved(fileURL: finished.fileURL, endReason: reason))
        } else {
            transition(.interrupted(reason: reason))
        }
    }

    // MARK: Sample routing

    private func routeVideoSample(_ wrapped: SendableSample) async {
        guard let pipeline = pipeline else { return }
        let sample = wrapped.buffer
        guard let imgBuf = CMSampleBufferGetImageBuffer(sample) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        await pipeline.appendVideo(pixelBuffer: imgBuf, presentationTime: pts)
        pixelFrames += 1
    }

    private func routeSystemAudioSample(_ wrapped: SendableSample) async {
        await mixer?.acceptSystem(wrapped)
    }

    private func routeMicSample(_ wrapped: SendableSample) async {
        await mixer?.acceptMic(wrapped)
    }

    private func routeMixedAudio(_ wrapped: SendableSample) async {
        await pipeline?.appendAudio(sampleBuffer: wrapped)
    }

    private func routeMicChanged() async {
        await logger.log(.audioDeviceChanged, .warn, [
            "recording_id": inFlight?.id.uuidString ?? ""
        ])
    }

    private func handleStreamError(_ reason: EndReason) async {
        await stopWithReason(reason)
    }

    // MARK: Helpers

    private func transition(_ new: CaptureState) {
        state = new
        let cb = onStateChange
        cb?(new)
    }

    private func isFinishedState(_ s: CaptureState) -> Bool {
        switch s {
        case .saved, .interrupted, .errorPermission, .errorRuntime: return true
        default: return false
        }
    }
}

// MARK: - SCStream delegate proxy

private final class StreamProxy: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let onVideo: (CMSampleBuffer) -> Void
    let onSystemAudio: (CMSampleBuffer) -> Void
    let onError: (EndReason) -> Void

    init(
        onVideo: @escaping (CMSampleBuffer) -> Void,
        onSystemAudio: @escaping (CMSampleBuffer) -> Void,
        onError: @escaping (EndReason) -> Void
    ) {
        self.onVideo = onVideo
        self.onSystemAudio = onSystemAudio
        self.onError = onError
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            onVideo(sampleBuffer)
        case .audio:
            onSystemAudio(sampleBuffer)
        case .microphone:
            // macOS 15+ added a microphone output channel on SCStream itself.
            // We don't subscribe it (we use AVCaptureSession for mic), but the
            // switch must be exhaustive.
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // SCK errors when the captured window/display disappears.
        let nsErr = error as NSError
        // Heuristic: if it's "user content unavailable" / "window-no-longer-on-screen",
        // map to .targetGone; else .systemSignal.
        if nsErr.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
            onError(.targetGone)
        } else {
            onError(.systemSignal)
        }
    }
}
