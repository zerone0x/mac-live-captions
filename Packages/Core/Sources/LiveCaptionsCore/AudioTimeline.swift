import Foundation

/// Keeps converted audio on the session time axis, in whole samples.
///
/// The speech adapter resamples `AudioChunk`s into the analyzer's format and
/// gives every buffer an explicit start, so result time ranges are in session
/// seconds. All output time is kept as an integer frame index at the
/// analyzer's sample rate (`sampleRate`): a buffer starts exactly where the
/// previous one ended, with no `Double` seconds in between that could round
/// one sample early (issue #48, DECISIONS 0024).
///
/// A chunk that does not follow the previous one (first chunk, gap or overlap
/// beyond `tolerance`) re-anchors the timeline; the adapter then resets its
/// resampler. The new anchor is the chunk's start rounded to a whole output
/// frame, but never earlier than the end of audio already placed:
/// `SpeechAnalyzer` rejects input that starts before earlier input ends, so
/// such audio is kept and shifted later.
public struct AudioTimeline: Sendable, Hashable {
    /// Output (analyzer) sample rate: frames per second of every placed buffer.
    public let sampleRate: Int
    /// Largest mismatch, in seconds, still treated as contiguous audio.
    public let tolerance: TimeInterval

    private var expectedNextInput: TimeInterval?
    /// Output frame index where the next placed buffer starts.
    private var nextFrame: Int64 = 0
    /// End of the audio placed so far, in output frames.
    public private(set) var placedEnd: Int64?

    public init(sampleRate: Int, tolerance: TimeInterval = 0.02) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        precondition(tolerance >= 0, "tolerance must not be negative")
        self.sampleRate = sampleRate
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
            let chunkFrame = SampleTime.frame(atSeconds: chunkStart, sampleRate: sampleRate)
            nextFrame = max(chunkFrame, placedEnd ?? chunkFrame)
        }
        expectedNextInput = chunkStart + max(0, duration)
        return discontinuous
    }

    /// Start frame of the next output buffer, which has `frames` frames;
    /// advances the timeline past it.
    public mutating func place(frames: Int) -> Int64 {
        let start = nextFrame
        nextFrame += Int64(max(0, frames))
        placedEnd = nextFrame
        return start
    }
}

/// Conversions between session seconds and whole frames.
public enum SampleTime {
    /// The frame nearest to `seconds`, never negative. Non-finite input maps to 0.
    public static func frame(atSeconds seconds: TimeInterval, sampleRate: Int) -> Int64 {
        precondition(sampleRate > 0, "sampleRate must be positive")
        let exact = seconds * Double(sampleRate)
        guard exact.isFinite, exact > 0 else { return 0 }
        guard exact < Double(Int64.max / 2) else { return Int64.max / 2 }
        return Int64(exact.rounded())
    }

    /// Session seconds of `frame` (for display and result mapping only, never
    /// for analyzer input times).
    public static func seconds(ofFrame frame: Int64, sampleRate: Int) -> TimeInterval {
        precondition(sampleRate > 0, "sampleRate must be positive")
        return Double(frame) / Double(sampleRate)
    }
}

/// Last check before an input reaches `SpeechAnalyzer`.
///
/// Every input must start at or after the end (start + real frame count) of
/// the input before it. The guard is fed the start the timeline computed and
/// the buffer's real `frameLength`; a start that would overlap is moved to the
/// previous end, so an overlapping input is never fed (DECISIONS 0024).
public struct MonotonicInputGuard: Sendable, Hashable {
    /// End of the last admitted input, in frames.
    public private(set) var end: Int64?
    /// How many inputs had to be moved later. Stays 0 when the timeline is right.
    public private(set) var shiftedInputs = 0

    public init() {}

    /// The start to feed for an input of `frames` frames proposed at `start`,
    /// or `nil` for an empty input (which is not fed).
    public mutating func admit(start: Int64, frames: Int) -> Int64? {
        guard frames > 0 else { return nil }
        var admitted = max(0, start)
        if let end, admitted < end {
            admitted = end
            shiftedInputs += 1
        }
        end = admitted + Int64(frames)
        return admitted
    }
}

/// How often a failed analyzer session may be restarted (DECISIONS 0024).
///
/// At most `maxRestarts` restarts within any `window` seconds of session
/// time; beyond that the error is reported and captions stop, so a failure
/// that repeats at once cannot turn into a restart loop.
public struct AnalyzerRestartBudget: Sendable, Hashable {
    public static let defaultMaxRestarts = 3
    public static let defaultWindow: TimeInterval = 300

    public let maxRestarts: Int
    public let window: TimeInterval
    private var restarts: [TimeInterval] = []

    public init(maxRestarts: Int = Self.defaultMaxRestarts, window: TimeInterval = Self.defaultWindow) {
        precondition(maxRestarts >= 0, "maxRestarts must not be negative")
        precondition(window > 0, "window must be positive")
        self.maxRestarts = maxRestarts
        self.window = window
    }

    /// Restarts used in the window that ends at the last request.
    public var recentRestarts: Int { restarts.count }

    /// Asks for a restart at session time `now`. Returns `true` and records
    /// it when the budget allows one.
    public mutating func requestRestart(at now: TimeInterval) -> Bool {
        restarts.removeAll { now - $0 >= window }
        guard restarts.count < maxRestarts else { return false }
        restarts.append(now)
        return true
    }
}
