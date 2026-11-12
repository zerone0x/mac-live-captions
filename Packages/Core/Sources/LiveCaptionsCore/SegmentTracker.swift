import Foundation

/// One raw recogniser result, before it has a stable segment ID.
///
/// The speech adapter fills this from `SpeechTranscriber.Result` (text, audio
/// time range in session seconds, `isFinal`). Keeping it a plain value type
/// lets the ID rules below be tested without the Speech framework.
public struct RecognizedPhrase: Sendable, Hashable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var isFinal: Bool

    public init(text: String, start: TimeInterval, end: TimeInterval, isFinal: Bool) {
        self.text = text
        self.start = start
        self.end = end
        self.isFinal = isFinal
    }
}

/// Gives recogniser results stable segment IDs.
///
/// `SpeechTranscriber` sends each phrase one or more times as volatile results
/// and then once as a final result, in order. The tracker keeps one "open"
/// segment: volatile results reuse its ID, and the final result that covers it
/// closes it with the same ID. The next volatile result opens a new segment.
///
/// A final result that ends before the open segment starts belongs to an
/// earlier phrase: it gets its own ID and the open segment stays open.
///
/// Text is trimmed. Time ranges are made safe for `TranscriptSegment`
/// (finite, non-negative, `end >= start`).
public struct SegmentTracker: Sendable {
    public let origin: AudioOrigin

    private var open: (id: SegmentID, start: TimeInterval)?
    private var lastEnd: TimeInterval = 0

    public init(origin: AudioOrigin) {
        self.origin = origin
    }

    /// The ID volatile results currently update, if any.
    public var openSegmentID: SegmentID? { open?.id }

    /// Returns the event for `phrase`, or `nil` when it carries nothing to show
    /// (empty text and no open segment to clear).
    public mutating func event(for phrase: RecognizedPhrase) -> TranscriptEvent? {
        let text = phrase.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let (start, end) = sanitizedRange(phrase)

        if phrase.isFinal {
            lastEnd = max(lastEnd, end)
            let id: SegmentID
            let closesOpen: Bool
            if let open, !(end <= open.start && start < open.start) {
                // Covers the open phrase: finalize it under the same ID.
                id = open.id
                closesOpen = true
                self.open = nil
            } else {
                // No open phrase, or an earlier phrase (the open one stays open).
                id = SegmentID()
                closesOpen = false
            }
            if text.isEmpty {
                // An empty final only matters if it closes a volatile line.
                return closesOpen ? .final(segment(id, "", start, end)) : nil
            }
            return .final(segment(id, text, start, end))
        }

        if text.isEmpty {
            // Tentative text vanished: clear the line but keep the ID open.
            guard let open else { return nil }
            return .volatile(segment(open.id, "", start, end))
        }
        let id: SegmentID
        if let open {
            id = open.id
            self.open = (id, min(open.start, start))
        } else {
            id = SegmentID()
            self.open = (id, start)
        }
        return .volatile(segment(id, text, start, end))
    }

    /// Forgets the open segment (for example when the audio stream restarts).
    public mutating func reset() {
        open = nil
        lastEnd = 0
    }

    private func segment(_ id: SegmentID, _ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(id: id, text: text, start: start, end: end, origin: origin)
    }

    private func sanitizedRange(_ phrase: RecognizedPhrase) -> (TimeInterval, TimeInterval) {
        let start = phrase.start.isFinite ? max(0, phrase.start) : lastEnd
        let end = phrase.end.isFinite ? max(start, phrase.end) : start
        return (start, end)
    }
}
