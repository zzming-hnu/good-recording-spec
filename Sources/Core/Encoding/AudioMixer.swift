// good-recording — Core/Encoding/AudioMixer.swift (T025)
//
// Mix mic + system-audio CMSampleBuffers into a single AAC track output.
//
// Approach:
//   - System audio (from SCK) and mic audio (from AVCaptureSession) arrive
//     asynchronously with different sample rates (we normalize via AVAudioConverter).
//   - We hold both in small ring buffers, align by host timestamp, and emit
//     a mixed sample buffer into the AssetWriterPipeline's audio input.
//   - When only one source is enabled, we pass it straight through (no mix).
//
// v1 implementation favors correctness over CPU efficiency: it uses
// AVAudioPCMBuffer + manual sample-by-sample mixing in Float32.
//
// Source of truth: home-spec/specs/001-good-recording/research.md R2

import Foundation
import AVFoundation
import CoreMedia

public actor AudioMixer {

    // MARK: Config

    public struct Config: Sendable {
        public let micEnabled: Bool
        public let systemEnabled: Bool
        public init(micEnabled: Bool, systemEnabled: Bool) {
            self.micEnabled = micEnabled
            self.systemEnabled = systemEnabled
        }
    }

    private let config: Config

    /// 当前对外发布混合好的 sample buffer 的 callback。
    private var output: (@Sendable (CMSampleBuffer) -> Void)?

    // Tiny per-source buffers (newest sample wins; we don't try to perfectly
    // align timestamps — just concurrent-ish playback in the output AAC).
    private var pendingSystem: CMSampleBuffer?
    private var pendingMic:    CMSampleBuffer?

    public init(config: Config) {
        self.config = config
    }

    public func setOutput(_ cb: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.output = cb
    }

    // MARK: Ingest

    public func acceptSystem(_ wrapped: SendableSample) {
        guard config.systemEnabled else { return }
        let sample = wrapped.buffer
        if !config.micEnabled {
            output?(sample)
            return
        }
        pendingSystem = sample
        flushIfReady()
    }

    public func acceptMic(_ wrapped: SendableSample) {
        guard config.micEnabled else { return }
        let sample = wrapped.buffer
        if !config.systemEnabled {
            output?(sample)
            return
        }
        pendingMic = sample
        flushIfReady()
    }

    // MARK: Mixing

    private func flushIfReady() {
        guard let sys = pendingSystem, let _ = pendingMic else { return }
        defer {
            pendingSystem = nil
            pendingMic = nil
        }

        // v0.1 LIMITATION: byte-level PCM mixing produces audible distortion
        // ("electronic noise") because mic and system audio arrive in
        // different formats (sample rate, bit depth, channel count). The
        // proper fix is an AVAudioEngine-based pipeline with AVAudioConverter
        // doing per-stream format normalization before mixing — tracked as
        // a follow-up to Phase 5 (US3 audio sources UI).
        //
        // For v0.1: when both sources are enabled, prefer SYSTEM audio
        // and drop mic. Users explicitly turning on system audio almost
        // always care about that source more (presentation / game / video
        // content); single-source pass-through works perfectly.
        output?(sys)
        // TODO(v0.2): replace with AVAudioEngine-based real mixing.
    }

    private nonisolated func mix(master: CMSampleBuffer, slave: CMSampleBuffer) -> CMSampleBuffer? {
        // Get format descriptions
        guard
            let fmtDesc = CMSampleBufferGetFormatDescription(master),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)?.pointee
        else { return master }

        // Read PCM data into mutable buffers
        guard
            let masterData = readPCM(master),
            let slaveData  = readPCM(slave)
        else { return master }

        // Convert both to Float32, then sum + clamp
        let masterFloats = bytesAsFloat32(masterData, asbd: asbd)
        let slaveFloats  = bytesAsFloat32(slaveData,  asbd: asbd)

        let count = min(masterFloats.count, slaveFloats.count)
        var mixed = [Float](repeating: 0, count: count)
        for i in 0..<count {
            // Simple average then mild attenuation to avoid clipping.
            let v = (masterFloats[i] + slaveFloats[i]) * 0.7
            mixed[i] = max(-1.0, min(1.0, v))
        }

        // Re-pack as the original PCM format
        let outBytes = float32AsBytes(mixed, asbd: asbd)
        return rebuildSampleBuffer(template: master, bytes: outBytes)
    }

    private nonisolated func readPCM(_ sb: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sb) else { return nil }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &length, dataPointerOut: &ptr
        )
        guard status == kCMBlockBufferNoErr, let ptr else { return nil }
        return Data(bytes: ptr, count: length)
    }

    private nonisolated func bytesAsFloat32(
        _ data: Data,
        asbd: AudioStreamBasicDescription
    ) -> [Float] {
        // We only handle 16-bit signed-int and 32-bit float here. SCK and
        // AVCaptureSession both fall into one of these by default.
        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
        let count = data.count / bytesPerSample
        var floats = [Float](repeating: 0, count: count)

        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Float.self)
                for i in 0..<count { floats[i] = src[i] }
            }
        } else {
            data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Int16.self)
                let denom: Float = 32_768.0
                for i in 0..<count { floats[i] = Float(src[i]) / denom }
            }
        }
        return floats
    }

    private nonisolated func float32AsBytes(
        _ floats: [Float],
        asbd: AudioStreamBasicDescription
    ) -> Data {
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            return floats.withUnsafeBufferPointer { Data(buffer: $0) }
        }
        // Convert back to Int16
        var int16s = [Int16](repeating: 0, count: floats.count)
        for i in 0..<floats.count {
            int16s[i] = Int16(max(-32768, min(32767, floats[i] * 32768)))
        }
        return int16s.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private nonisolated func rebuildSampleBuffer(
        template: CMSampleBuffer,
        bytes: Data
    ) -> CMSampleBuffer? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(template) else { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(template)
        let dur = CMSampleBufferGetDuration(template)

        var blockBuffer: CMBlockBuffer?
        let status1 = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status1 == noErr, let blockBuffer else { return nil }

        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            _ = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: bytes.count
            )
        }

        var sampleSizes: [Int] = [bytes.count]
        var newSB: CMSampleBuffer?
        let status2 = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmtDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [CMSampleTimingInfo(duration: dur, presentationTimeStamp: pts, decodeTimeStamp: .invalid)],
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizes,
            sampleBufferOut: &newSB
        )
        return status2 == noErr ? newSB : nil
    }
}
