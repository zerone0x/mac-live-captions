import Foundation
import Testing

@testable import LiveCaptionsCore

private func phrase(_ text: String, _ start: TimeInterval, _ end: TimeInterval, final: Bool = false) -> RecognizedPhrase
{
    RecognizedPhrase(text: text, start: start, end: end, isFinal: final)
}

@Suite("SegmentTracker")
struct SegmentTrackerTests {
    @Test("volatile results of one phrase share an ID and the final keeps it")
    func stableIDAcrossPhrase() throws {
        var tracker = SegmentTracker(origin: .system)
        let result1 = tracker.event(for: phrase("hel", 0, 0.5))
        let first = try #require(result1)
        let result2 = tracker.event(for: phrase("hello world", 0, 1.2))
        let second = try #require(result2)
        let result3 = tracker.event(for: phrase("Hello world.", 0, 1.3, final: true))
        let final = try #require(result3)

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
        let result4 = tracker.event(for: phrase("one", 0, 1, final: true))
        let a = try #require(result4)
        let result5 = tracker.event(for: phrase("two", 1, 2))
        let b = try #require(result5)
        let result6 = tracker.event(for: phrase("Two.", 1, 2, final: true))
        let c = try #require(result6)
        #expect(a.segment.id != b.segment.id)
        #expect(b.segment.id == c.segment.id)
    }

    @Test("a final for an earlier phrase does not close the open phrase")
    func earlierFinalKeepsOpenPhrase() throws {
        var tracker = SegmentTracker(origin: .microphone)
        let result7 = tracker.event(for: phrase("later words", 3, 4))
        let open = try #require(result7)
        let result8 = tracker.event(for: phrase("Earlier.", 1, 2.5, final: true))
        let earlier = try #require(result8)
        #expect(earlier.segment.id != open.segment.id)
        #expect(tracker.openSegmentID == open.segment.id)

        let result9 = tracker.event(for: phrase("Later words.", 3, 4.2, final: true))
        let closing = try #require(result9)
        #expect(closing.segment.id == open.segment.id)
    }

    @Test("a final that overlaps the open phrase closes it")
    func overlappingFinalCloses() throws {
        var tracker = SegmentTracker(origin: .system)
        let result10 = tracker.event(for: phrase("a b c", 2, 5))
        let open = try #require(result10)
        let result11 = tracker.event(for: phrase("A b.", 1.8, 3, final: true))
        let final = try #require(result11)
        #expect(final.segment.id == open.segment.id)
        #expect(tracker.openSegmentID == nil)
    }

    @Test("the open phrase's start follows the earliest volatile result")
    func openStartMovesBack() throws {
        var tracker = SegmentTracker(origin: .system)
        let result12 = tracker.event(for: phrase("words", 3, 4))
        let open = try #require(result12)
        _ = tracker.event(for: phrase("more words", 2, 4))
        // Ends after 2.0, so it overlaps the open phrase as last reported.
        let result13 = tracker.event(for: phrase("More words.", 2, 2.5, final: true))
        let final = try #require(result13)
        #expect(final.segment.id == open.segment.id)
    }

    @Test("a later volatile result with a later start does not move the open phrase's start forward")
    func openStartNeverMovesForward() throws {
        var tracker = SegmentTracker(origin: .system)
        let result = tracker.event(for: phrase("words", 2, 3))
        let open = try #require(result)
        _ = tracker.event(for: phrase("words and more", 3, 4))
        // Ends after 2.0, where the phrase started: it covers the open phrase.
        let finalResult = tracker.event(for: phrase("Words.", 2, 2.5, final: true))
        let final = try #require(finalResult)
        #expect(final.segment.id == open.segment.id)
        #expect(tracker.openSegmentID == nil)
    }

    @Test("empty results: nothing to show unless a volatile line must be cleared")
    func emptyResults() throws {
        var tracker = SegmentTracker(origin: .system)
        let result14 = tracker.event(for: phrase("  ", 0, 1))
        #expect(result14 == nil)
        let result15 = tracker.event(for: phrase("", 0, 1, final: true))
        #expect(result15 == nil)

        let result16 = tracker.event(for: phrase("um", 1, 2))
        let open = try #require(result16)
        let result17 = tracker.event(for: phrase("", 1, 2))
        let cleared = try #require(result17)
        #expect(
            cleared == .volatile(TranscriptSegment(id: open.segment.id, text: "", start: 1, end: 2, origin: .system)))
        #expect(tracker.openSegmentID == open.segment.id)

        let result18 = tracker.event(for: phrase(" ", 1, 2, final: true))
        let closed = try #require(result18)
        #expect(closed.isFinal)
        #expect(closed.segment.id == open.segment.id)
        #expect(closed.segment.text == "")
        #expect(tracker.openSegmentID == nil)
    }

    @Test("text is trimmed")
    func trims() throws {
        var tracker = SegmentTracker(origin: .system)
        let result19 = tracker.event(for: phrase(" Hello. ", 0, 1, final: true))
        let event = try #require(result19)
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
        let result20 = tracker.event(for: phrase("x", start, end, final: true))
        let event = try #require(result20)
        #expect(event.segment.start == expectedStart)
        #expect(event.segment.end == expectedEnd)
    }

    @Test("a missing start time falls back to the end of the last final")
    func missingStartUsesLastEnd() throws {
        var tracker = SegmentTracker(origin: .system)
        _ = tracker.event(for: phrase("first", 0, 4, final: true))
        let result21 = tracker.event(for: phrase("second", .nan, .nan, final: true))
        let event = try #require(result21)
        #expect(event.segment.start == 4)
        #expect(event.segment.end == 4)
    }

    @Test("a late final for an earlier phrase does not move the fallback start back")
    func lastEndOnlyGrows() throws {
        var tracker = SegmentTracker(origin: .system)
        _ = tracker.event(for: phrase("first", 0, 4, final: true))
        _ = tracker.event(for: phrase("earlier", 1, 2, final: true))
        let result = tracker.event(for: phrase("second", .nan, .nan, final: true))
        let event = try #require(result)
        #expect(event.segment.start == 4)
    }

    @Test("reset forgets the open phrase")
    func reset() throws {
        var tracker = SegmentTracker(origin: .system)
        let result22 = tracker.event(for: phrase("half", 0, 1))
        let before = try #require(result22)
        tracker.reset()
        #expect(tracker.openSegmentID == nil)
        let result23 = tracker.event(for: phrase("half", 0, 1))
        let after = try #require(result23)
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
