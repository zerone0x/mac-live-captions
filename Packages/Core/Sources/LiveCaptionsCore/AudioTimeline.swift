import Foundation

/// Keeps converted audio on the session time axis.
///
/// The speech adapter resamples `AudioChunk`s into the analyzer's format and
/// gives every buffer an explicit start time, so result time ranges are in
/// session seconds. Output time is counted in output frames from an anchor
/// (no drift from rounding chunk times). A chunk that does not follow the
/// previous one (first chunk, gap or overlap beyond `tolerance`) re-anchors
/// the timeline; the adapter then resets its resampler.
public struct AudioTimeline: Sendable, Hashable {
    /// Largest mismatch, in seconds, still treated as contiguous audio.
    public let tolerance: TimeInterval

    private var expectedNextInput: TimeInterval?
    private var anchor: TimeInterval = 0
    private var outputFrames: Int64 = 0

    public init(tolerance: TimeInterval = 0.02) {
        precondition(tolerance >= 0, "tolerance must not be negative")
        self.tolerance = tolerance
    }

    /// Registers an input chunk. Returns `true` when it starts a new
    /// contiguous run (the caller should reset its converter).
    public mutating func accept(chunkStart: TimeInterval, duration: TimeInterval) -> Bool {
        let discontinuous: Bool
        if let expected = expectedNextInput {
            discontinuous = abs(chunkStart - expected) > tolerance
        } else {
            discontinuous = true
        }
        if discontinuous {
            anchor = chunkStart
            outputFrames = 0
        }
        expectedNextInput = chunkStart + max(0, duration)
        return discontinuous
    }

    /// Start time of the next output buffer, which has `frames` frames at
    /// `sampleRate`; advances the timeline past it.
    public mutating func place(frames: Int, sampleRate: Double) -> TimeInterval {
        precondition(sampleRate > 0, "sampleRate must be positive")
        let start = anchor + Double(outputFrames) / sampleRate
        outputFrames += Int64(max(0, frames))
        return start
    }
}
