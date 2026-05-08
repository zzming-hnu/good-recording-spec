// good-recording — Core/Capture/SendableSample.swift
//
// CMSampleBuffer is not Sendable in Swift 6. We wrap it in an
// `@unchecked Sendable` envelope so we can hand sample buffers across
// actor / Task boundaries without cloning. CMSampleBuffer is a
// reference-counted CoreFoundation type and is safe to ferry across
// threads as long as we don't mutate it (we never do — we only read).

@preconcurrency import CoreMedia

public struct SendableSample: @unchecked Sendable {
    public let buffer: CMSampleBuffer
    public init(_ buffer: CMSampleBuffer) { self.buffer = buffer }
}
