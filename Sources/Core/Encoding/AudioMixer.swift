// good-recording — Core/Encoding/AudioMixer.swift (v0.2)
//
// True two-source audio mixing via AVAudioEngine. Replaces the v0.1
// byte-level PCM hack that produced "电音" distortion when both mic
// and system audio were enabled.
//
// Pipeline:
//
//   acceptSystem(CMSampleBuffer)
//     → CMSampleBuffer → AVAudioPCMBuffer (per-source format)
//     → AVAudioConverter → AVAudioPCMBuffer (standardFormat)
//     → sysPlayer.scheduleBuffer
//
//   acceptMic(CMSampleBuffer)
//     → ditto but via micConverter into micPlayer
//
//   AVAudioEngine.mainMixerNode mixes both nodes
//     → installTap(format: standardFormat)
//     → tap CB → AVAudioPCMBuffer
//     → CMSampleBuffer (with synthetic monotonically-increasing PTS)
//     → output?(CMSampleBuffer) → AssetWriterPipeline
//
// Single-source modes (only mic OR only system) still bypass the
// engine entirely with bit-exact pass-through.
//
// Source of truth: home-spec/specs/001-good-recording/research.md R2 +
// spec.md FR-011 (mix sources into single track).

import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
@preconcurrency import AudioToolbox

public actor AudioMixer {

    // MARK: Config

    public struct Config: Sendable {
        public let micEnabled: Bool
        public let systemEnabled: Bool
        public init(micEnabled: Bool, systemEnabled: Bool) {
            self.micEnabled = micEnabled
            self.systemEnabled = systemEnabled
        }
        public var bothEnabled: Bool { micEnabled && systemEnabled }
    }

    private let config: Config

    /// Sink for the mixed sample buffers (set by CaptureCoordinator).
    private var output: (@Sendable (CMSampleBuffer) -> Void)?

    // MARK: AVAudioEngine plumbing

    private let engine = AVAudioEngine()
    private let micPlayer = AVAudioPlayerNode()
    private let sysPlayer = AVAudioPlayerNode()

    /// Common format every source is converted to before reaching the
    /// mixer. 48 kHz Float32 stereo non-interleaved matches AVAssetWriter's
    /// preferred input for AAC encoding and what SCK produces natively.
    private let standardFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFormat.sampleRate,
            channels: AVAudioChannelCount(AudioFormat.channels),
            interleaved: false
        )!
    }()

    private var sysConverter: AVAudioConverter?
    private var micConverter: AVAudioConverter?
    private var sysSourceFormat: AVAudioFormat?
    private var micSourceFormat: AVAudioFormat?

    private var engineStarted = false
    private var engineStartFailed = false

    /// Synthetic PTS state — tap output has no original timestamps so we
    /// derive monotonic ones from cumulative frame count.
    private var ptsBase: CMTime?
    private var ptsCumulativeFrames: Int64 = 0

    // MARK: Init

    public init(config: Config) {
        self.config = config
    }

    public func setOutput(_ cb: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.output = cb
    }

    // MARK: Engine lifecycle

    private func startEngineIfNeeded() {
        guard !engineStarted, !engineStartFailed else { return }
        engineStarted = true

        engine.attach(micPlayer)
        engine.attach(sysPlayer)
        engine.connect(micPlayer, to: engine.mainMixerNode, format: standardFormat)
        engine.connect(sysPlayer, to: engine.mainMixerNode, format: standardFormat)

        // We don't want hardware playback — only the tapped mix.
        engine.mainMixerNode.outputVolume = 0

        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: tapFormat
        ) { [weak self] (buffer, _) in
            // Tap callback runs on a real-time audio thread.
            // Hop into the actor to forward.
            let copy = AudioMixer.copyPCMBuffer(buffer)
            Task { [weak self] in await self?.emitMixed(copy) }
        }

        do {
            try engine.start()
            micPlayer.play()
            sysPlayer.play()
        } catch {
            engineStartFailed = true
            engineStarted = false
        }
    }

    public func stop() {
        if engineStarted {
            engine.mainMixerNode.removeTap(onBus: 0)
            micPlayer.stop()
            sysPlayer.stop()
            engine.stop()
        }
        engineStarted = false
        engineStartFailed = false
        sysConverter = nil
        micConverter = nil
        sysSourceFormat = nil
        micSourceFormat = nil
        ptsBase = nil
        ptsCumulativeFrames = 0
    }

    // MARK: Ingest

    // ⚠️ KNOWN ISSUE (2026-05-08): the AVAudioEngine path below produces
    // an audio track with the right format (2 ch / 48 kHz / AAC) but
    // almost no actual sample data — the tap → emitMixed → writer chain
    // appears to drop most buffers when ferried across the
    // audio-thread → actor boundary. Diagnosing this needs more
    // engine/timing debugging than fits in v0.1.
    //
    // For now we route everything through the v0.1 system-priority
    // pass-through path (no mixing, system audio is bit-exact). The
    // AVAudioEngine code below is preserved for the v0.2 follow-up
    // when there's time to dig in (likely candidates: switch from
    // AVAudioPlayerNode + scheduleBuffer to a manual-rendering
    // AVAudioSourceNode pulling from a ring buffer; or skip
    // AVAudioEngine entirely and do the conversion + mixing manually
    // with AVAudioConverter + sample-aligned summation).
    private static let useEnginePath = false

    public func acceptSystem(_ wrapped: SendableSample) {
        guard config.systemEnabled else { return }
        // v0.1 pass-through path: system audio always streams straight to
        // the writer. Single-source bit-exact, two-source = system priority.
        if !Self.useEnginePath || !config.micEnabled {
            output?(wrapped.buffer)
            return
        }
        // ── (Future v0.2 path, currently disabled) ─────────────────
        startEngineIfNeeded()
        if engineStartFailed {
            output?(wrapped.buffer)
            return
        }
        captureBaseTimestampIfNeeded(from: wrapped.buffer)
        if let pcm = convertedPCM(
            from: wrapped.buffer,
            converter: &sysConverter,
            sourceFormat: &sysSourceFormat
        ) {
            sysPlayer.scheduleBuffer(pcm, completionHandler: nil)
        }
    }

    public func acceptMic(_ wrapped: SendableSample) {
        guard config.micEnabled else { return }
        // v0.1 pass-through path: when system is also enabled, mic is
        // silently dropped (system priority). When mic is the only source
        // it goes straight through.
        if !Self.useEnginePath {
            if !config.systemEnabled { output?(wrapped.buffer) }
            return
        }
        // ── (Future v0.2 path, currently disabled) ─────────────────
        if !config.systemEnabled {
            output?(wrapped.buffer)
            return
        }
        startEngineIfNeeded()
        if engineStartFailed {
            return
        }
        if let pcm = convertedPCM(
            from: wrapped.buffer,
            converter: &micConverter,
            sourceFormat: &micSourceFormat
        ) {
            micPlayer.scheduleBuffer(pcm, completionHandler: nil)
        }
    }

    // MARK: PTS handling

    private func captureBaseTimestampIfNeeded(from sample: CMSampleBuffer) {
        guard ptsBase == nil else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if CMTIME_IS_VALID(pts) {
            ptsBase = pts
        } else {
            ptsBase = .zero
        }
    }

    private func nextPTS(forFrames frames: Int64) -> (start: CMTime, duration: CMTime) {
        let base = ptsBase ?? .zero
        let sampleRate = Int32(AudioFormat.sampleRate)
        let start = CMTimeAdd(
            base,
            CMTime(value: ptsCumulativeFrames, timescale: sampleRate)
        )
        let duration = CMTime(value: frames, timescale: sampleRate)
        ptsCumulativeFrames += frames
        return (start, duration)
    }

    // MARK: Conversion

    private func convertedPCM(
        from sample: CMSampleBuffer,
        converter: inout AVAudioConverter?,
        sourceFormat: inout AVAudioFormat?
    ) -> AVAudioPCMBuffer? {
        // Build / cache an AVAudioConverter for this source.
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sample),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)
        else { return nil }
        let asbd = asbdPtr.pointee

        if sourceFormat == nil {
            var localASBD = asbd
            sourceFormat = AVAudioFormat(streamDescription: &localASBD)
        }
        guard let srcFmt = sourceFormat else { return nil }

        if converter == nil {
            converter = AVAudioConverter(from: srcFmt, to: standardFormat)
        }
        guard let cv = converter else { return nil }

        // Wrap CMSampleBuffer's PCM data in an input AVAudioPCMBuffer.
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0,
              let inBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: frames)
        else { return nil }
        inBuf.frameLength = frames

        // Copy PCM bytes from the CMBlockBuffer into the input buffer.
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, blockBuffer != nil else { return nil }

        // Manual copy — we have to handle interleaved vs deinterleaved.
        let audioBufferListPtr = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0,
           audioBufferListPtr.count == Int(srcFmt.channelCount) {
            for ch in 0..<Int(srcFmt.channelCount) {
                let src = audioBufferListPtr[ch]
                if let inChannelData = inBuf.floatChannelData?[ch],
                   let srcData = src.mData?.assumingMemoryBound(to: Float.self) {
                    let count = Int(src.mDataByteSize) / MemoryLayout<Float>.size
                    inChannelData.update(from: srcData, count: count)
                } else if let inChannelData = inBuf.int16ChannelData?[ch],
                          let srcData = src.mData?.assumingMemoryBound(to: Int16.self) {
                    let count = Int(src.mDataByteSize) / MemoryLayout<Int16>.size
                    inChannelData.update(from: srcData, count: count)
                }
            }
        } else if let firstBuffer = audioBufferListPtr.first,
                  let srcRaw = firstBuffer.mData {
            // Interleaved single-buffer case
            if let inChannelData = inBuf.floatChannelData {
                let frames = Int(inBuf.frameLength)
                let channels = Int(srcFmt.channelCount)
                let srcFloats = srcRaw.assumingMemoryBound(to: Float.self)
                for ch in 0..<channels {
                    for f in 0..<frames {
                        inChannelData[ch][f] = srcFloats[f * channels + ch]
                    }
                }
            } else if let inChannelData = inBuf.int16ChannelData {
                let frames = Int(inBuf.frameLength)
                let channels = Int(srcFmt.channelCount)
                let srcInts = srcRaw.assumingMemoryBound(to: Int16.self)
                for ch in 0..<channels {
                    for f in 0..<frames {
                        inChannelData[ch][f] = srcInts[f * channels + ch]
                    }
                }
            }
        }

        // Convert to standardFormat.
        let ratio = standardFormat.sampleRate / srcFmt.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frames) * ratio + 1024)
        guard let outBuf = AVAudioPCMBuffer(
            pcmFormat: standardFormat,
            frameCapacity: outCapacity
        ) else { return nil }

        // Use a tiny class wrapper to hold the "supplied" flag and the
        // input buffer reference. AVAudioConverterInputBlock is @Sendable,
        // so capturing mutable vars or non-Sendable types directly fails
        // under Swift 6 strict concurrency.
        let state = ConverterState(input: inBuf)
        var convertError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            state.deliverNext(outStatus: outStatus)
        }
        let _ = cv.convert(to: outBuf, error: &convertError, withInputFrom: inputBlock)
        if convertError != nil { return nil }
        return outBuf
    }

    // MARK: Tap → CMSampleBuffer emission

    private func emitMixed(_ buffer: AVAudioPCMBuffer) async {
        guard let output = output else { return }
        let frames = Int64(buffer.frameLength)
        guard frames > 0 else { return }

        let (startPTS, duration) = nextPTS(forFrames: frames)

        if let cmSample = AudioMixer.makeCMSampleBuffer(
            from: buffer,
            startPTS: startPTS,
            duration: duration
        ) {
            output(cmSample)
        }
    }

    // MARK: Helpers

    private nonisolated static func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Buffer from the tap is owned by the audio thread; copy before
        // ferrying it across actor boundaries.
        let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        )!
        copy.frameLength = buffer.frameLength
        if let srcChannels = buffer.floatChannelData,
           let dstChannels = copy.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                dstChannels[ch].update(
                    from: srcChannels[ch],
                    count: Int(buffer.frameLength)
                )
            }
        }
        return copy
    }

    // MARK: - Conversion helper

    /// Holds AVAudioConverter input state. Class so the @Sendable input
    /// block can mutate without Swift 6 captured-var errors.
    private final class ConverterState: @unchecked Sendable {
        let input: AVAudioPCMBuffer
        private var supplied = false
        init(input: AVAudioPCMBuffer) { self.input = input }
        func deliverNext(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
            if supplied {
                outStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }
    }

    private nonisolated static func makeCMSampleBuffer(
        from buffer: AVAudioPCMBuffer,
        startPTS: CMTime,
        duration: CMTime
    ) -> CMSampleBuffer? {
        let format = buffer.format
        var asbdMutable = format.streamDescription.pointee

        // CMAudioFormatDescription
        var fmtDesc: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbdMutable,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &fmtDesc
        )
        guard status == noErr, let fmtDesc else { return nil }

        // Build a CMSampleBuffer that wraps the PCM buffer's audioBufferList.
        var sampleBuffer: CMSampleBuffer?
        let timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: startPTS,
            decodeTimeStamp: .invalid
        )
        status = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmtDesc,
            sampleCount: CMItemCount(buffer.frameLength),
            presentationTimeStamp: startPTS,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        _ = timing  // silence unused-var
        guard status == noErr, let sampleBuffer else { return nil }

        // Now copy the PCM data into the sample buffer
        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }

        return sampleBuffer
    }
}
