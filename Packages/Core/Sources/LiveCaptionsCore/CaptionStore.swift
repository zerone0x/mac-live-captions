import Foundation

/// Turns transcriber events into the caption state the overlay shows.
///
/// Rules (see docs/DECISIONS.md, 0008):
///
/// - A segment keeps its `SegmentID` from its first volatile result to its
///   final result, so the overlay can update a line in place.
/// - A volatile event replaces the volatile text of its segment in place. Each
///   origin has at most one volatile segment; a volatile event with a new ID
///   replaces the previous volatile segment of the same origin.
/// - A final event moves the segment into the transcript. Finalized segments
///   are immutable: later volatile or final events for the same ID are ignored.
/// - The transcript is bounded: only the newest `historyLimit` finalized
///   segments are kept. IDs of dropped segments are still remembered (also
///   bounded), so a late event cannot bring a dropped segment back.
///
/// Pure value type with no clock and no I/O, so it is fully unit-tested.
public struct CaptionStore: Sendable {
    /// Limits of the store.
    public struct Configuration: Sendable, Hashable {
        /// Maximum number of finalized segments kept in `transcript`.
        public var historyLimit: Int
        /// Number of finalized lines shown above the volatile line.
        public var visibleFinalLines: Int

        public init(historyLimit: Int = 500, visibleFinalLines: Int = 2) {
            precondition(historyLimit >= 1, "historyLimit must be at least 1")
            precondition(visibleFinalLines >= 0, "visibleFinalLines must not be negative")
            self.historyLimit = historyLimit
            self.visibleFinalLines = min(visibleFinalLines, historyLimit)
        }
    }

    /// What `apply(_:)` did with an event.
    public enum Outcome: Sendable, Hashable {
        /// A volatile line was added or its text replaced.
        case volatileUpdated
        /// A volatile line was removed (empty volatile result, or an empty final).
        case volatileCleared
        /// A segment was added to the transcript.
        case finalized
        /// Nothing changed (event for an already final segment, or empty text
        /// with nothing to clear).
        case ignored

        /// Whether the visible state may have changed.
        public var changedState: Bool { self != .ignored }
    }

    public let configuration: Configuration

    /// Finalized segments, oldest first. Never longer than `historyLimit`.
    public private(set) var transcript: [TranscriptSegment] = []

    /// Current volatile segment per origin.
    private var volatileByOrigin: [AudioOrigin: TranscriptSegment] = [:]

    /// IDs that reached a final result: the retained ones plus a bounded
    /// memory of dropped ones.
    private var finalIDs: Set<SegmentID> = []
    /// Insertion order of `finalIDs`, used to bound it.
    private var finalIDOrder: [SegmentID] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Volatile segments, ordered by start time (ties by origin).
    public var volatileSegments: [TranscriptSegment] {
        volatileByOrigin.values.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.origin.rawValue < rhs.origin.rawValue
        }
    }

    /// Whether `id` has been finalized (and is therefore immutable).
    public func isFinal(_ id: SegmentID) -> Bool {
        finalIDs.contains(id)
    }

    /// The transcript as plain text, segments separated by a space.
    public var transcriptText: String {
        transcript.map(\.text).joined(separator: " ")
    }

    /// What the overlay shows now: the newest `visibleFinalLines` finalized
    /// segments, then the volatile segments. Empty means hide.
    public var snapshot: CaptionSnapshot {
        let finals = transcript.suffix(configuration.visibleFinalLines).map {
            CaptionLine(id: $0.id, text: $0.text, origin: $0.origin, isFinal: true)
        }
        let volatiles = volatileSegments.map {
            CaptionLine(id: $0.id, text: $0.text, origin: $0.origin, isFinal: false)
        }
        return CaptionSnapshot(lines: finals + volatiles)
    }

    /// Applies one transcriber event.
    @discardableResult
    public mutating func apply(_ event: TranscriptEvent) -> Outcome {
        switch event {
        case .volatile(let segment):
            applyVolatile(segment)
        case .final(let segment):
            applyFinal(segment)
        }
    }

    /// Applies events in order and returns whether any of them changed state.
    @discardableResult
    public mutating func apply<Events: Sequence>(_ events: Events) -> Bool where Events.Element == TranscriptEvent {
        var changed = false
        for event in events {
            if apply(event).changedState {
                changed = true
            }
        }
        return changed
    }

    /// Clears everything, for a new session.
    public mutating func reset() {
        self = CaptionStore(configuration: configuration)
    }

    // MARK: - Private

    private mutating func applyVolatile(_ segment: TranscriptSegment) -> Outcome {
        guard !finalIDs.contains(segment.id) else { return .ignored }

        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            // The recogniser has no tentative text right now: hide the line.
            guard volatileByOrigin[segment.origin] != nil else { return .ignored }
            volatileByOrigin[segment.origin] = nil
            return .volatileCleared
        }

        var updated = segment
        updated.text = text
        if volatileByOrigin[segment.origin] == updated { return .ignored }
        volatileByOrigin[segment.origin] = updated
        return .volatileUpdated
    }

    private mutating func applyFinal(_ segment: TranscriptSegment) -> Outcome {
        guard !finalIDs.contains(segment.id) else { return .ignored }
        rememberFinal(segment.id)

        let clearedVolatile = removeVolatile(id: segment.id)
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // Nothing was said after all: drop the volatile line, keep no line.
            return clearedVolatile ? .volatileCleared : .ignored
        }

        var final = segment
        final.text = text
        transcript.append(final)
        if transcript.count > configuration.historyLimit {
            transcript.removeFirst(transcript.count - configuration.historyLimit)
        }
        return .finalized
    }

    private mutating func removeVolatile(id: SegmentID) -> Bool {
        guard let origin = volatileByOrigin.first(where: { $0.value.id == id })?.key else { return false }
        volatileByOrigin[origin] = nil
        return true
    }

    private mutating func rememberFinal(_ id: SegmentID) {
        finalIDs.insert(id)
        finalIDOrder.append(id)
        // Remember dropped IDs for as long as the transcript itself is long.
        let limit = configuration.historyLimit * 2
        if finalIDOrder.count > limit {
            let overflow = finalIDOrder.count - limit
            for old in finalIDOrder.prefix(overflow) {
                finalIDs.remove(old)
            }
            finalIDOrder.removeFirst(overflow)
        }
    }
}
