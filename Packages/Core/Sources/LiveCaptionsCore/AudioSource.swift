import Foundation

/// Where a stream of audio comes from.
///
/// The caption pipeline uses system audio only; the microphone is used only by
/// the debug capture test (docs/DECISIONS.md, 0014). Nothing reads the origin
/// to label speakers, and no speaker is inferred (docs/SCOPE.md).
public enum AudioOrigin: String, Sendable, Hashable, Codable, CaseIterable {
    case system
    case microphone
}

/// A block of mono Float32 PCM samples.
///
/// Core stays free of AVFoundation types so that every stage can be faked in
/// plain unit tests. Platform adapters convert from and to `AVAudioPCMBuffer`.
public struct AudioChunk: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Double
    public var origin: AudioOrigin
    /// Seconds since the capture session started.
    public var startTime: TimeInterval

    public init(samples: [Float], sampleRate: Double, origin: AudioOrigin, startTime: TimeInterval) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        self.samples = samples
        self.sampleRate = sampleRate
        self.origin = origin
        self.startTime = startTime
    }

    /// Length of the chunk in seconds.
    public var duration: TimeInterval {
        Double(samples.count) / sampleRate
    }

    /// Session time at which the chunk ends.
    public var endTime: TimeInterval {
        startTime + duration
    }
}

/// Produces audio for the caption pipeline.
///
/// Real implementations (ScreenCaptureKit system audio, microphone) live in the
/// app target; tests use fakes that yield prepared chunks.
public protocol AudioSource: Sendable {
    var origin: AudioOrigin { get }

    /// Starts capturing and returns the stream of chunks. The stream finishes
    /// after `stop()` and throws if capture fails (for example, permission denied).
    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error>

    /// Stops capturing. Safe to call when not running.
    func stop() async
}
