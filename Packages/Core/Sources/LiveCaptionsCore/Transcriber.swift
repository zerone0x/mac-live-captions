import Foundation

/// Stable identifier of a transcript segment.
///
/// Volatile results for the same utterance keep the same ID, so the caption
/// store can replace the volatile text when the final result arrives.
public struct SegmentID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

/// A piece of recognised speech with its time range and origin.
public struct TranscriptSegment: Sendable, Hashable, Identifiable {
    public var id: SegmentID
    public var text: String
    /// Session time range covered by the segment, in seconds.
    public var start: TimeInterval
    public var end: TimeInterval
    public var origin: AudioOrigin

    public init(id: SegmentID = SegmentID(), text: String, start: TimeInterval, end: TimeInterval, origin: AudioOrigin) {
        precondition(end >= start, "segment end must not be before its start")
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.origin = origin
    }
}

/// Output of a transcriber.
///
/// `volatile` results may still change and only drive the live caption line.
/// `final` results are stable and go into the transcript.
public enum TranscriptEvent: Sendable, Hashable {
    case volatile(TranscriptSegment)
    case final(TranscriptSegment)

    public var segment: TranscriptSegment {
        switch self {
        case .volatile(let segment), .final(let segment): segment
        }
    }

    public var isFinal: Bool {
        if case .final = self { true } else { false }
    }
}

/// Turns audio into transcript events, on device.
///
/// The real implementation wraps Apple's `SpeechAnalyzer` + `SpeechTranscriber`
/// (en-US) in the app target. It must not make network calls.
public protocol Transcriber: Sendable {
    func transcribe(
        _ audio: AsyncThrowingStream<AudioChunk, any Error>
    ) -> AsyncThrowingStream<TranscriptEvent, any Error>
}
