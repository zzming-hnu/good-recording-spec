// good-recording — Tests/UnitTests/_Mocks/CaptureSourceMock.swift (T026)
//
// Test fakes that let unit tests exercise capture/encode logic without TCC.
// Usage:
//   let mock = CaptureSourceMock()
//   await mock.emitFakeFrame()
// See: home-spec/specs/001-good-recording/quickstart.md §4

import Foundation
import CoreMedia
import CoreVideo

/// 一个轻量"capture source"接口 —— 真实 SCK 走自己的 SCStream，但
/// 我们的 unit test 通过这个接口注入 fake frames + audio buffers，
/// 验证 CaptureCoordinator 的状态机 + 错误映射，而不需要 TCC。
public protocol CaptureSource: AnyObject, Sendable {
    func startEmitting() async
    func stopEmitting() async
}

public final class CaptureSourceMock: CaptureSource, @unchecked Sendable {

    public var onVideo: ((CMSampleBuffer) -> Void)?
    public var onAudio: ((CMSampleBuffer) -> Void)?

    public init() {}

    public func startEmitting() async {
        // No-op; tests call emit* directly to control timing.
    }

    public func stopEmitting() async {
        onVideo = nil
        onAudio = nil
    }

    /// Push a synthetic 1080p BGRA black frame.
    public func emitFakeFrame(at pts: CMTime = .zero) {
        guard let pixelBuffer = makeBlackPixelBuffer(width: 1920, height: 1080),
              let sb = wrapPixelBuffer(pixelBuffer, pts: pts)
        else { return }
        onVideo?(sb)
    }

    private func makeBlackPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        return pb
    }

    private func wrapPixelBuffer(_ pb: CVPixelBuffer, pts: CMTime) -> CMSampleBuffer? {
        var fmtDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescriptionOut: &fmtDesc
        )
        guard let fmtDesc else { return nil }
        var info = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sb: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmtDesc,
            sampleTiming: &info,
            sampleBufferOut: &sb
        )
        return sb
    }
}

// MARK: - AssetWriter test fake

/// 一个最小的"writer"接口 —— 让 RecordingViewModel 测试不用真起 AVAssetWriter。
/// 真实代码用 AssetWriterPipeline 实现这个 protocol；测试用 AssetWriterMock。
public protocol WriterProtocol: AnyObject, Sendable {
    func start() async throws
    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) async
    func appendAudio(sampleBuffer: CMSampleBuffer) async
    func finishWriting() async throws -> (fileURL: URL, sizeBytes: Int64)
    func cancel() async
}

public final class AssetWriterMock: WriterProtocol, @unchecked Sendable {

    public enum MockError: Error { case forced(String) }

    public var receivedVideoFrames: Int = 0
    public var receivedAudioBuffers: Int = 0
    public var startCalled: Bool = false
    public var finishCalled: Bool = false
    public var cancelCalled: Bool = false

    /// 测试想要的最终输出。
    public var stubFinishURL: URL = URL(fileURLWithPath: "/tmp/good-recording-mock.mp4")
    public var stubFinishSize: Int64 = 1_234_567
    public var stubFinishError: Error?

    public init() {}

    public func start() async throws {
        startCalled = true
    }

    public func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) async {
        receivedVideoFrames += 1
    }

    public func appendAudio(sampleBuffer: CMSampleBuffer) async {
        receivedAudioBuffers += 1
    }

    public func finishWriting() async throws -> (fileURL: URL, sizeBytes: Int64) {
        finishCalled = true
        if let err = stubFinishError { throw err }
        return (stubFinishURL, stubFinishSize)
    }

    public func cancel() async {
        cancelCalled = true
    }
}
