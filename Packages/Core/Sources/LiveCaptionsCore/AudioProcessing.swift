import Foundation

/// Format the audio sources deliver to the transcriber: mono Float32 at 16 kHz.
///
/// 16 kHz mono is what on-device speech recognisers work at; sources convert
/// to it (with `AVAudioConverter` in the app target) before chunking.
public enum CaptureFormat {
    public static let sampleRate: Double = 16_000
    /// Length of one `AudioChunk` the sources emit.
    public static let chunkDuration: TimeInterval = 0.1

    /// Output frames to allocate when converting `inputFrames` frames from
    /// `inputRate` to `outputRate`. Rounds up and adds headroom for the
    /// frames a sample-rate converter may still hold from the previous call.
    public static func convertedFrameCapacity(
        inputFrames: Int,
        inputRate: Double,
        outputRate: Double,
        headroom: Int = 64
    ) -> Int {
        precondition(inputRate > 0 && outputRate > 0, "sample rates must be positive")
        guard inputFrames > 0 else { return headroom }
        let exact = Double(inputFrames) * outputRate / inputRate
        return Int(exact.rounded(.up)) + headroom
    }
}

/// Peak and RMS level of a block of samples, for the input meter and the
/// silence detector.
public struct AudioLevel: Sendable, Hashable {
    /// Largest absolute sample value, 0...1 for well-formed audio.
    public var peak: Float
    /// Root mean square of the samples.
    public var rms: Float

    /// Levels at or below this many decibels show as an empty meter.
    public static let meterFloorDecibels: Float = -60

    public static let silence = AudioLevel(peak: 0, rms: 0)

    public init(peak: Float, rms: Float) {
        self.peak = peak
        self.rms = rms
    }

    public init(samples: [Float]) {
        guard !samples.isEmpty else {
            self = .silence
            return
        }
        var peak: Float = 0
        var sumOfSquares: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak { peak = magnitude }
            sumOfSquares += sample * sample
        }
        self.init(peak: peak, rms: (sumOfSquares / Float(samples.count)).squareRoot())
    }

    /// RMS level in dBFS, clamped to -100 for silence.
    public var decibels: Float {
        guard rms > 0 else { return -100 }
        return max(-100, 20 * log10(rms))
    }

    /// Meter position in 0...1: `meterFloorDecibels` maps to 0, 0 dBFS to 1.
    public var meterFraction: Double {
        let floor = Self.meterFloorDecibels
        let clamped = min(0, max(floor, decibels))
        return Double((clamped - floor) / -floor)
    }
}

/// Cuts a continuous mono sample stream into fixed-length `AudioChunk`s and
/// stamps each with its session time.
///
/// Session time counts captured frames, not wall-clock time, so chunk times
/// line up exactly with the audio the transcriber sees.
public struct AudioChunkAssembler: Sendable {
    public let origin: AudioOrigin
    public let sampleRate: Double
    public let framesPerChunk: Int

    private var pending: [Float] = []
    private var emittedFrames = 0

    public init(
        origin: AudioOrigin,
        sampleRate: Double = CaptureFormat.sampleRate,
        chunkDuration: TimeInterval = CaptureFormat.chunkDuration
    ) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        precondition(chunkDuration > 0, "chunkDuration must be positive")
        self.origin = origin
        self.sampleRate = sampleRate
        self.framesPerChunk = max(1, Int((sampleRate * chunkDuration).rounded()))
    }

    /// Seconds of audio received so far, including samples not yet emitted.
    public var capturedDuration: TimeInterval {
        Double(emittedFrames + pending.count) / sampleRate
    }

    /// Adds samples and returns every chunk that is now complete.
    public mutating func append(_ samples: [Float]) -> [AudioChunk] {
        pending.append(contentsOf: samples)
        var chunks: [AudioChunk] = []
        var offset = 0
        while pending.count - offset >= framesPerChunk {
            let slice = Array(pending[offset..<(offset + framesPerChunk)])
            chunks.append(makeChunk(slice))
            offset += framesPerChunk
        }
        if offset > 0 {
            pending.removeFirst(offset)
        }
        return chunks
    }

    /// Emits the remaining samples as a shorter final chunk, if there are any.
    public mutating func flush() -> AudioChunk? {
        guard !pending.isEmpty else { return nil }
        let chunk = makeChunk(pending)
        pending.removeAll()
        return chunk
    }

    /// Starts a new session: time goes back to zero and pending samples are dropped.
    public mutating func reset() {
        pending.removeAll()
        emittedFrames = 0
    }

    private mutating func makeChunk(_ samples: [Float]) -> AudioChunk {
        let chunk = AudioChunk(
            samples: samples,
            sampleRate: sampleRate,
            origin: origin,
            startTime: Double(emittedFrames) / sampleRate
        )
        emittedFrames += samples.count
        return chunk
    }
}

/// Detects "capture runs but nothing is playing".
///
/// Works on a clock (monotonic seconds) rather than on the length of the
/// audio it was fed, so it is right whether or not the capture API delivers
/// buffers of silence: call `process(_:at:)` for every block that arrives and
/// `check(at:)` from a timer. It reports `.silenceDetected` once when nothing
/// louder than `threshold` arrived for `timeout` seconds, and
/// `.soundDetected` on the first loud block after that.
public struct SilenceMonitor: Sendable {
    /// Peak at or below this counts as silence (about -80 dBFS).
    public let threshold: Float
    public let timeout: TimeInterval

    /// When the current quiet stretch began: the last loud block, or the
    /// start of monitoring. `nil` until the first call.
    private var quietSince: TimeInterval?
    private var reportedSilence = false

    public init(threshold: Float = 1e-4, timeout: TimeInterval = 5) {
        precondition(timeout > 0, "timeout must be positive")
        self.threshold = threshold
        self.timeout = timeout
    }

    /// Whether silence has been reported and not yet ended.
    public var isSilent: Bool { reportedSilence }

    /// Whether a block with this level counts as silence.
    public func isSilence(_ level: AudioLevel) -> Bool {
        level.peak <= threshold
    }

    /// A block of audio with `level` arrived at `now`.
    public mutating func process(_ level: AudioLevel, at now: TimeInterval) -> AudioCaptureEvent? {
        guard isSilence(level) else {
            quietSince = now
            if reportedSilence {
                reportedSilence = false
                return .soundDetected
            }
            return nil
        }
        return check(at: now)
    }

    /// Reports silence if nothing loud arrived for `timeout` seconds before
    /// `now`, including when no audio arrived at all.
    public mutating func check(at now: TimeInterval) -> AudioCaptureEvent? {
        guard let quietSince else {
            self.quietSince = now
            return nil
        }
        // Tolerance: sums of block lengths like 0.1 s drift below the exact total.
        guard !reportedSilence, now - quietSince + 1e-9 >= timeout else { return nil }
        reportedSilence = true
        return .silenceDetected
    }

    /// Starts monitoring afresh at `now`, for a new or reconnected stream.
    public mutating func reset(at now: TimeInterval) {
        quietSince = now
        reportedSilence = false
    }
}

/// When to reconnect after a capture stream stops unexpectedly.
///
/// Exponential backoff (2, 4, 8, … seconds, capped), a bounded number of
/// attempts, and never for a denied permission: retrying would only show the
/// system prompt again, and the grant needs an app relaunch anyway.
public struct CaptureRetryPolicy: Sendable, Hashable {
    public var maxAttempts: Int
    public var maxDelay: TimeInterval

    public init(maxAttempts: Int = 6, maxDelay: TimeInterval = 30) {
        self.maxAttempts = maxAttempts
        self.maxDelay = maxDelay
    }

    /// Delay before reconnect attempt `attempt` (1-based), or `nil` to give up.
    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= maxAttempts else { return nil }
        return min(maxDelay, pow(2, Double(attempt)))
    }
}
