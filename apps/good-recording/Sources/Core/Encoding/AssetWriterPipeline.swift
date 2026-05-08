// good-recording — Core/Encoding/AssetWriterPipeline.swift (T024)
//
// AVAssetWriter wrapper. Owns the temp file lifecycle:
//   1. tmp/recording-{id}.{ext}.partial during capture
//   2. atomic rename to final URL on finishWriting().completed
// Inserts container metadata (title / creator / creationDate / preset blob)
// per contracts/output-files.md.
//
// Source of truth:
//   home-spec/specs/001-good-recording/contracts/output-files.md
//   home-spec/specs/001-good-recording/data-model.md V4–V6

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

public actor AssetWriterPipeline {

    // MARK: Public types

    public enum PipelineError: LocalizedError, Sendable {
        case writerSetupFailed(String)
        case finishFailed(String)
        case validationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .writerSetupFailed(let m): return "Writer setup failed: \(m)"
            case .finishFailed(let m):      return "Finish failed: \(m)"
            case .validationFailed(let m):  return "Validation failed: \(m)"
            }
        }
    }

    public struct Config: Sendable {
        public let recordingID: UUID
        public let mode: RecordingMode
        public let videoConfig: VideoConfig?     // .video 必须有
        public let audioSources: AudioSourceSet
        public let sourceVideoSize: CGSize?      // .video 必须有；.audioOnly 用 nil
        public let containerFormat: ContainerFormat
        public let saveDirectoryURL: URL
        public let finalFileURL: URL

        public init(
            recordingID: UUID,
            mode: RecordingMode,
            videoConfig: VideoConfig?,
            audioSources: AudioSourceSet,
            sourceVideoSize: CGSize?,
            containerFormat: ContainerFormat,
            saveDirectoryURL: URL,
            finalFileURL: URL
        ) {
            self.recordingID = recordingID
            self.mode = mode
            self.videoConfig = videoConfig
            self.audioSources = audioSources
            self.sourceVideoSize = sourceVideoSize
            self.containerFormat = containerFormat
            self.saveDirectoryURL = saveDirectoryURL
            self.finalFileURL = finalFileURL
        }
    }

    // MARK: Internal state

    private let config: Config
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var sessionStartTime: CMTime = .zero
    private let tempURL: URL

    // MARK: Init

    public init(config: Config) {
        self.config = config
        self.tempURL = RecordingFileNamer.tempFileURL(
            in: FileManager.default.temporaryDirectory,
            recordingID: config.recordingID,
            format: config.containerFormat
        )
    }

    // MARK: Lifecycle

    public func start() async throws {
        let writer: AVAssetWriter
        do {
            // Wipe any previous .partial leftover at this exact tmp path.
            try? FileManager.default.removeItem(at: tempURL)
            writer = try AVAssetWriter(url: tempURL, fileType: config.containerFormat.avFileType)
        } catch {
            throw PipelineError.writerSetupFailed(error.localizedDescription)
        }

        // metadata
        writer.metadata = makeMetadataItems()

        // video input
        if config.mode == .video,
           let videoConfig = config.videoConfig,
           let size = config.sourceVideoSize {
            let outSize = resolveOutputSize(source: size, resolution: videoConfig.resolution)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey:  videoConfig.codec.avVideoCodecType.rawValue,
                AVVideoWidthKey:  Int(outSize.width),
                AVVideoHeightKey: Int(outSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: BitrateHeuristic.averageBitsPerSecond(for: videoConfig),
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoMaxKeyFrameIntervalKey: 60
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true

            let adaptorAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String:  Int(outSize.width),
                kCVPixelBufferHeightKey as String: Int(outSize.height)
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: adaptorAttrs
            )

            guard writer.canAdd(input) else {
                throw PipelineError.writerSetupFailed("cannot add video input")
            }
            writer.add(input)
            self.videoInput = input
            self.videoAdaptor = adaptor
        }

        // audio input — always present (silent track is legal per US3 AC4)
        let audioSettings: [String: Any] = [
            AVFormatIDKey:           AudioFormat.codec,
            AVSampleRateKey:         AudioFormat.sampleRate,
            AVNumberOfChannelsKey:   AudioFormat.channels,
            AVEncoderBitRateKey:     AudioFormat.bitRate
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(aInput) else {
            throw PipelineError.writerSetupFailed("cannot add audio input")
        }
        writer.add(aInput)
        self.audioInput = aInput

        guard writer.startWriting() else {
            throw PipelineError.writerSetupFailed(
                writer.error?.localizedDescription ?? "startWriting failed"
            )
        }
        self.writer = writer
    }

    /// 录制收到的第一个 sample 调用 — 把 session start 钉到那个时间戳上。
    public func beginSession(at presentationTime: CMTime) {
        guard let writer = writer, !sessionStarted else { return }
        writer.startSession(atSourceTime: presentationTime)
        sessionStartTime = presentationTime
        sessionStarted = true
    }

    /// 视频帧推入。
    public func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        if !sessionStarted { beginSession(at: presentationTime) }
        guard let adaptor = videoAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }

    /// 音频帧推入（已经混好的 sample buffer）。
    public func appendAudio(sampleBuffer wrapped: SendableSample) {
        let sampleBuffer = wrapped.buffer
        if !sessionStarted {
            beginSession(at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    /// 结束 — 标记 inputs done、await finish、原子改名、校验、返回最终 URL + 大小。
    ///
    /// Order matters: we move tmp → final FIRST, *then* run acceptance gate
    /// on the final URL. If we ran the gate on the `.partial` URL instead,
    /// AVURLAsset's type sniffing rejects the unknown extension and reports
    /// zero tracks even on a perfectly good file.
    public func finishWriting() async throws -> (fileURL: URL, sizeBytes: Int64) {
        guard let writer = writer else {
            throw PipelineError.finishFailed("writer was never started")
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        // suspend until finishWriting completes
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }

        guard writer.status == .completed else {
            throw PipelineError.finishFailed(
                writer.error?.localizedDescription ?? "writer status != completed (\(writer.status.rawValue))"
            )
        }

        // 1) Atomic move tmp → final. Doing this first means the acceptance
        //    gate below uses a URL that AVFoundation actually recognises by
        //    extension (.mp4 / .mov / .m4a).
        try FileManager.default.createDirectory(
            at: config.saveDirectoryURL,
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: config.finalFileURL.path) {
            try FileManager.default.removeItem(at: config.finalFileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: config.finalFileURL)

        // 2) Acceptance contract (contracts/output-files.md) on the final URL.
        let asset = AVURLAsset(url: config.finalFileURL)
        let tracks = (try? await asset.load(.tracks)) ?? []
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: config.finalFileURL.path)[.size] as? Int) ?? 0
        guard !tracks.isEmpty,
              duration >= 0.5,
              fileSize > 0 else {
            // Quarantine the moved file so the user can still recover it.
            let quarantineDir = config.saveDirectoryURL.appendingPathComponent("_failed", isDirectory: true)
            try? FileManager.default.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
            let quarantineURL = quarantineDir.appendingPathComponent("\(config.recordingID.uuidString).\(config.containerFormat.fileExtension)")
            try? FileManager.default.moveItem(at: config.finalFileURL, to: quarantineURL)
            throw PipelineError.validationFailed("acceptance gate failed (tracks=\(tracks.count), dur=\(duration), size=\(fileSize))")
        }

        return (config.finalFileURL, Int64(fileSize))
    }

    /// 错误中止 — 关掉 writer 并清掉残留 tmp，不写出最终文件。
    public func cancel() {
        writer?.cancelWriting()
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: Helpers

    private func makeMetadataItems() -> [AVMetadataItem] {
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = "good-recording" as NSString

        let creator = AVMutableMetadataItem()
        creator.identifier = .commonIdentifierCreator
        let info = Bundle.main.infoDictionary ?? [:]
        let v = (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let b = (info["CFBundleVersion"] as? String) ?? "0"
        creator.value = "good-recording/\(v) (Build \(b))" as NSString

        let creation = AVMutableMetadataItem()
        creation.identifier = .commonIdentifierCreationDate
        creation.value = ISO8601DateFormatter().string(from: Date()) as NSString

        let desc = AVMutableMetadataItem()
        desc.identifier = .commonIdentifierDescription
        let blob: [String: Any] = [
            "recording_id": config.recordingID.uuidString,
            "mode":         config.mode.rawValue,
            "container":    config.containerFormat.rawValue,
            "audio":        ["ambient": config.audioSources.ambient,
                             "system":  config.audioSources.system]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: blob, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            desc.value = str as NSString
        } else {
            desc.value = "" as NSString
        }

        return [title, creator, creation, desc]
    }

    private func resolveOutputSize(source: CGSize, resolution: VideoResolution) -> CGSize {
        guard let shortSide = resolution.shortSidePixels else { return source }
        let aspect = source.width / max(source.height, 1)
        if source.width <= source.height {
            let w = CGFloat(shortSide)
            return CGSize(width: w, height: round(w / aspect))
        } else {
            let h = CGFloat(shortSide)
            return CGSize(width: round(h * aspect), height: h)
        }
    }
}
