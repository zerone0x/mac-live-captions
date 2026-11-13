import Foundation

/// One rendered line of the caption overlay.
///
/// `id` counts lines since the composer was created (or reset), so a line keeps
/// its identity while it scrolls up. `volatileText` is the part the recogniser
/// may still revise; it is drawn lighter and always comes after `finalText`.
public struct CaptionDisplayLine: Sendable, Hashable, Identifiable {
    public var id: Int
    public var finalText: String
    /// Starts with a space when `finalText` is not empty, so
    /// `finalText + volatileText` is the full line.
    public var volatileText: String

    public init(id: Int, finalText: String, volatileText: String) {
        self.id = id
        self.finalText = finalText
        self.volatileText = volatileText
    }

    public var text: String { finalText + volatileText }

    public var hasVolatileText: Bool { !volatileText.isEmpty }
}

/// What the overlay draws: at most `maxLines` lines, oldest first.
public struct CaptionFrame: Sendable, Hashable {
    public var lines: [CaptionDisplayLine]

    public init(lines: [CaptionDisplayLine] = []) {
        self.lines = lines
    }

    public static let empty = CaptionFrame()

    public var isEmpty: Bool { lines.isEmpty }
}

/// Turns caption snapshots into overlay frames and decides when the overlay
/// collapses.
///
/// Layout rules (docs/DECISIONS.md, 0008):
/// - At most `maxLines` lines of at most `maxLineLength` characters, left
///   aligned, wrapped greedily at word boundaries.
/// - Finalized text is append-only: once laid out, it never changes, rewraps
///   or moves sideways. Only the volatile tail at the end can change.
/// - Lines scroll up as text grows. The view does not scroll back down when a
///   volatile revision gets shorter, unless that would leave it showing no
///   text at all.
/// - After `idleTimeout` seconds without new text the overlay collapses. Text
///   that arrives after that starts on a fresh line.
///
/// Pure value type: the caller passes the time, so tests need no clock.
public struct CaptionComposer: Sendable {
    public struct Configuration: Sendable, Hashable {
        public var maxLines: Int
        public var maxLineLength: Int
        public var idleTimeout: TimeInterval

        /// Two lines of 42 characters: the usual limit for English subtitles.
        public static let english = Configuration(maxLines: 2, maxLineLength: 42, idleTimeout: 6)

        public init(maxLines: Int, maxLineLength: Int, idleTimeout: TimeInterval) {
            precondition(maxLines > 0, "maxLines must be positive")
            precondition(maxLineLength > 0, "maxLineLength must be positive")
            precondition(idleTimeout > 0, "idleTimeout must be positive")
            self.maxLines = maxLines
            self.maxLineLength = maxLineLength
            self.idleTimeout = idleTimeout
        }
    }

    public let configuration: Configuration
    public private(set) var frame: CaptionFrame = .empty

    /// Finalized words from the first line we still keep onwards.
    private var committed: [String] = []
    /// Segments whose final text is already in `committed`.
    private var committedIDs: Set<SegmentID> = []
    /// Current volatile words, after `committed`.
    private var tail: [String] = []
    /// Line number of the first line of `committed`.
    private var firstLineNumber = 0
    /// Line number of the top visible line. Only moves forward, except when
    /// the text shrinks below it.
    private var topLineNumber = 0
    private var lastActivity: TimeInterval?

    public init(configuration: Configuration = .english) {
        self.configuration = configuration
    }

    /// Whether the overlay should be visible at time `now`.
    public func isExpanded(at now: TimeInterval) -> Bool {
        guard let deadline = collapseDeadline else { return false }
        return now < deadline
    }

    /// When the overlay collapses unless new text arrives first.
    /// `nil` when there is nothing to show.
    public var collapseDeadline: TimeInterval? {
        guard !frame.isEmpty, let lastActivity else { return nil }
        return lastActivity + configuration.idleTimeout
    }

    /// Applies the latest snapshot and returns the new frame.
    ///
    /// An empty snapshot clears everything. A snapshot that does not change
    /// the text leaves the frame and the idle timer alone.
    @discardableResult
    public mutating func apply(_ snapshot: CaptionSnapshot, at now: TimeInterval) -> CaptionFrame {
        if snapshot.isEmpty {
            reset()
            return frame
        }

        let width = configuration.maxLineLength
        var newlyFinal: [String] = []
        for line in snapshot.lines where line.isFinal && !committedIDs.contains(line.id) {
            committedIDs.insert(line.id)
            newlyFinal += CaptionLineBreaker.pieces(of: line.text, maxLineLength: width)
        }
        // One volatile line at most: the newest one. Volatile lines of two
        // origins (system audio and microphone) are never joined, so their
        // words cannot interleave (docs/DECISIONS.md, 0014).
        let volatileLine = snapshot.lines.last { !$0.isFinal && !committedIDs.contains($0.id) }
        let volatile = volatileLine.map { CaptionLineBreaker.pieces(of: $0.text, maxLineLength: width) } ?? []
        // Keep the ID set bounded: segments the store no longer reports are done.
        committedIDs.formIntersection(snapshot.lines.map(\.id))

        guard !newlyFinal.isEmpty || volatile != tail else {
            return frame
        }

        if let lastActivity, now >= lastActivity + configuration.idleTimeout {
            startFreshParagraph()
        }

        committed += newlyFinal
        tail = volatile
        lastActivity = now
        layOut()
        return frame
    }

    /// Forgets all text, as after an empty snapshot.
    public mutating func reset() {
        let nextLine = nextUnusedLineNumber()
        committed = []
        committedIDs = []
        tail = []
        firstLineNumber = nextLine
        topLineNumber = nextLine
        lastActivity = nil
        frame = .empty
    }

    // MARK: - Test seams

    /// Finalized words still held. Read by tests that check the composer
    /// drops text that scrolled out of view.
    var committedWordCount: Int { committed.count }
    /// Segment IDs still remembered as committed. Read by tests that check
    /// the set stays bounded.
    var committedIDCount: Int { committedIDs.count }

    // MARK: - Private

    private func nextUnusedLineNumber() -> Int {
        (frame.lines.last?.id).map { $0 + 1 } ?? max(firstLineNumber, topLineNumber)
    }

    /// After an idle collapse, old text is dropped and new text starts on a
    /// new line, so the overlay does not reopen with stale captions.
    private mutating func startFreshParagraph() {
        let nextLine = nextUnusedLineNumber()
        committed = []
        tail = []
        firstLineNumber = nextLine
        topLineNumber = nextLine
    }

    private mutating func layOut() {
        let width = configuration.maxLineLength
        let maxLines = configuration.maxLines
        let words = committed + tail
        let lines = CaptionLineBreaker.lines(of: words, maxLineLength: width)

        guard !lines.isEmpty else {
            frame = .empty
            return
        }

        let lastLineNumber = firstLineNumber + lines.count - 1
        var top = max(topLineNumber, lastLineNumber - maxLines + 1)
        top = min(top, lastLineNumber)
        top = max(top, firstLineNumber)
        topLineNumber = top

        let visible = (top - firstLineNumber)..<min(top - firstLineNumber + maxLines, lines.count)
        frame = CaptionFrame(lines: visible.map { index in
            let range = lines[index]
            let finalEnd = min(max(range.lowerBound, committed.count), range.upperBound)
            let finalText = words[range.lowerBound..<finalEnd].joined(separator: " ")
            var volatileText = words[finalEnd..<range.upperBound].joined(separator: " ")
            if !finalText.isEmpty && !volatileText.isEmpty {
                volatileText = " " + volatileText
            }
            return CaptionDisplayLine(id: firstLineNumber + index, finalText: finalText, volatileText: volatileText)
        })

        // Drop finalized lines that scrolled out of view. Keep the last line
        // that holds finalized text: new final words may still join it. Because
        // wrapping is prefix-stable, re-wrapping from a line start gives the
        // same lines as before.
        let committedLines = CaptionLineBreaker.lines(of: committed, maxLineLength: width)
        let droppable = max(0, min(committedLines.count - 1, top - firstLineNumber))
        if droppable > 0 {
            committed.removeFirst(committedLines[droppable].lowerBound)
            firstLineNumber += droppable
        }
    }
}
