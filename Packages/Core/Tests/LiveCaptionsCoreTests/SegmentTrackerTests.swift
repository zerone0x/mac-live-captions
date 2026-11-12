import Foundation
import Testing
@testable import LiveCaptionsCore

private func phrase(_ text: String, _ start: TimeInterval, _ end: TimeInterval, final: Bool = false) -> RecognizedPhrase {
    RecognizedPhrase(text: text, start: start, end: end, isFinal: final)
}

@Suite("SegmentTracker")
struct SegmentTrackerTests {
    @Test("volatile results of one phrase share an ID and the final keeps it")
    func stableIDAcrossPhrase() throws {
        var tracker = SegmentTracker(origin: .system)
        let first = try #require(tracker.event(for: phrase("hel", 0, 0.5)))
        let second = try #require(tracker.event(for: phrase("hello world", 0, 1.2)))
        let final = try #require(tracker.event(for: phrase("Hello world.", 0, 1.3, final: true)))

        #expect(!first.isFinal && !second.isFinal && final.isFinal)
        #expect(first.segment.id == second.segment.id)
        #expect(final.segment.id == first.segment.id)
        #expect(final.segment.text == "Hello world.")
        #expect(final.segment.origin == .system)
        #expect(tracker.openSegmentID == nil)
    }

    @Test("the next phrase after a final gets a new ID")
    func newIDAfterFinal() throws {
        var tracker = SegmentTracker(origin: .system)
        let a = try #require(tracker.event(for: phrase("one", 0, 1, final: true)))
        let b = try #require(tracker.event(for: phrase("two", 1, 2)))
        let c = try #require(tracker.event(for: phrase("Two.", 1, 2, final: true)))
        #expect(a.segment.id != b.segment.id)
        #expect(b.segment.id == c.segment.id)
    }

    @Test("a final for an earlier phrase does not close the open phrase")
    func earlierFinalKeepsOpenPhrase() throws {
        var tracker = SegmentTracker(origin: .microphone)
        let open = try #require(tracker.event(for: phrase("later words", 3, 4)))
        let earlier = try #require(tracker.event(for: phrase("Earlier.", 1, 2.5, final: true)))
        #expect(earlier.segment.id != open.segment.id)
        #expect(tracker.openSegmentID == open.segment.id)

        let closing = try #require(tracker.event(for: phrase("Later words.", 3, 4.2, final: true)))
        #expect(closing.segment.id == open.segment.id)
    }

    @Test("a final that overlaps the open phrase closes it")
    func overlappingFinalCloses() throws {
        var tracker = SegmentTracker(origin: .system)
        let open = try #require(tracker.event(for: phrase("a b c", 2, 5)))
        let final = try #require(tracker.event(for: phrase("A b.", 1.8, 3, final: true)))
        #expect(final.segment.id == open.segment.id)
        #expect(tracker.openSegmentID == nil)
    }

    @Test("the open phrase's start follows the earliest volatile result")
    func openStartMovesBack() throws {
        var tracker = SegmentTracker(origin: .system)
        let open = try #require(tracker.event(for: phrase("words", 3, 4)))
        _ = tracker.event(for: phrase("more words", 2, 4))
        // Ends after 2.0, so it overlaps the open phrase as last reported.
        let final = try #require(tracker.event(for: phrase("More words.", 2, 2.5, final: true)))
        #expect(final.segment.id == open.segment.id)
    }

    @Test("empty results: nothing to show unless a volatile line must be cleared")
    func emptyResults() throws {
        var tracker = SegmentTracker(origin: .system)
        #expect(tracker.event(for: phrase("  ", 0, 1)) == nil)
        #expect(tracker.event(for: phrase("", 0, 1, final: true)) == nil)

        let open = try #require(tracker.event(for: phrase("um", 1, 2)))
        let cleared = try #require(tracker.event(for: phrase("", 1, 2)))
        #expect(cleared == .volatile(TranscriptSegment(id: open.segment.id, text: "", start: 1, end: 2, origin: .system)))
        #expect(tracker.openSegmentID == open.segment.id)

        let closed = try #require(tracker.event(for: phrase(" ", 1, 2, final: true)))
        #expect(closed.isFinal)
        #expect(closed.segment.id == open.segment.id)
        #expect(closed.segment.text == "")
        #expect(tracker.openSegmentID == nil)
    }

    @Test("text is trimmed")
    func trims() throws {
        var tracker = SegmentTracker(origin: .system)
        let event = try #require(tracker.event(for: phrase(" Hello. ", 0, 1, final: true)))
        #expect(event.segment.text == "Hello.")
    }

    @Test(
        "invalid time ranges are made safe",
        arguments: [
            (Double.nan, 1.0, 0.0, 1.0),
            (2.0, Double.nan, 2.0, 2.0),
            (3.0, 1.0, 3.0, 3.0),
            (-1.0, 0.5, 0.0, 0.5),
            (Double.infinity, Double.infinity, 0.0, 0.0),
        ]
    )
    func sanitizesRanges(start: Double, end: Double, expectedStart: Double, expectedEnd: Double) throws {
        var tracker = SegmentTracker(origin: .system)
        let event = try #require(tracker.event(for: phrase("x", start, end, final: true)))
        #expect(event.segment.start == expectedStart)
        #expect(event.segment.end == expectedEnd)
    }

    @Test("a missing start time falls back to the end of the last final")
    func missingStartUsesLastEnd() throws {
        var tracker = SegmentTracker(origin: .system)
        _ = tracker.event(for: phrase("first", 0, 4, final: true))
        let event = try #require(tracker.event(for: phrase("second", .nan, .nan, final: true)))
        #expect(event.segment.start == 4)
        #expect(event.segment.end == 4)
    }

    @Test("reset forgets the open phrase")
    func reset() throws {
        var tracker = SegmentTracker(origin: .system)
        let before = try #require(tracker.event(for: phrase("half", 0, 1)))
        tracker.reset()
        #expect(tracker.openSegmentID == nil)
        let after = try #require(tracker.event(for: phrase("half", 0, 1)))
        #expect(after.segment.id != before.segment.id)
    }

    @Test("tracker events drive the caption store end to end")
    func trackerFeedsStore() {
        var tracker = SegmentTracker(origin: .system)
        var store = CaptionStore()
        let results = [
            phrase("this", 0, 0.3),
            phrase("this is", 0, 0.6),
            phrase("This is a test.", 0, 1.1, final: true),
            phrase("of live", 1.2, 1.8),
            phrase("of live captions", 1.2, 2.2),
        ]
        for result in results {
            if let event = tracker.event(for: result) {
                store.apply(event)
            }
        }
        #expect(store.snapshot.lines.map(\.text) == ["This is a test.", "of live captions"])
        #expect(store.snapshot.lines.map(\.isFinal) == [true, false])

        if let event = tracker.event(for: phrase("Of live captions.", 1.2, 2.3, final: true)) {
            store.apply(event)
        }
        #expect(store.transcriptText == "This is a test. Of live captions.")
        #expect(store.volatileSegments.isEmpty)
    }
}
