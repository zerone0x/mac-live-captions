import Foundation
import Testing

@testable import LiveCaptionsCore

private func seg(
    _ id: SegmentID,
    _ text: String,
    _ start: TimeInterval = 0,
    _ end: TimeInterval = 1,
    origin: AudioOrigin = .system
) -> TranscriptSegment {
    TranscriptSegment(id: id, text: text, start: start, end: end, origin: origin)
}

@Suite("CaptionStore")
struct CaptionStoreTests {
    @Test("a new store is empty and hides the overlay")
    func emptyStore() {
        let store = CaptionStore()
        #expect(store.transcript.isEmpty)
        #expect(store.volatileSegments.isEmpty)
        #expect(store.snapshot.isEmpty)
        #expect(store.transcriptText == "")
    }

    @Test("volatile text is replaced in place under the same ID")
    func volatileReplacedInPlace() {
        var store = CaptionStore()
        let id = SegmentID()

        let outcome1 = store.apply(.volatile(seg(id, "hel")))
        #expect(outcome1 == .volatileUpdated)
        let outcome2 = store.apply(.volatile(seg(id, "hello wor", 0, 1.5)))
        #expect(outcome2 == .volatileUpdated)
        let outcome3 = store.apply(.volatile(seg(id, "hello world", 0, 2)))
        #expect(outcome3 == .volatileUpdated)

        #expect(store.volatileSegments.count == 1)
        #expect(store.volatileSegments.first?.text == "hello world")
        #expect(store.volatileSegments.first?.end == 2)
        #expect(store.transcript.isEmpty)
        #expect(store.snapshot.lines == [CaptionLine(id: id, text: "hello world", origin: .system, isFinal: false)])
    }

    @Test("an identical volatile result changes nothing")
    func identicalVolatileIgnored() {
        var store = CaptionStore()
        let id = SegmentID()
        store.apply(.volatile(seg(id, "same")))
        let outcome4 = store.apply(.volatile(seg(id, "same")))
        #expect(outcome4 == .ignored)
    }

    @Test("the final result keeps the volatile line's ID and flips it to final")
    func finalKeepsID() {
        var store = CaptionStore()
        let id = SegmentID()
        store.apply(.volatile(seg(id, "hello wor")))
        let lineBefore = store.snapshot.lines.first

        let outcome5 = store.apply(.final(seg(id, "Hello world.")))
        #expect(outcome5 == .finalized)

        #expect(store.volatileSegments.isEmpty)
        #expect(store.transcript.map(\.text) == ["Hello world."])
        let lineAfter = store.snapshot.lines.first
        #expect(lineBefore?.id == lineAfter?.id)
        #expect(lineBefore?.isFinal == false)
        #expect(lineAfter?.isFinal == true)
        #expect(lineAfter?.text == "Hello world.")
        #expect(store.isFinal(id))
    }

    @Test("finalized segments are immutable: later finals and volatiles are ignored")
    func finalizedImmutable() {
        var store = CaptionStore()
        let id = SegmentID()
        store.apply(.final(seg(id, "First.")))

        let outcome6 = store.apply(.final(seg(id, "Rewritten.")))
        #expect(outcome6 == .ignored)
        let outcome7 = store.apply(.volatile(seg(id, "late volatile")))
        #expect(outcome7 == .ignored)

        #expect(store.transcript.map(\.text) == ["First."])
        #expect(store.volatileSegments.isEmpty)
    }

    @Test("a final without a preceding volatile is appended")
    func finalWithoutVolatile() {
        var store = CaptionStore()
        let outcome8 = store.apply(.final(seg(SegmentID(), "Short.")))
        #expect(outcome8 == .finalized)
        #expect(store.transcriptText == "Short.")
    }

    @Test("the next phrase opens a new volatile line below the finalized ones")
    func phraseSequence() {
        var store = CaptionStore()
        let first = SegmentID()
        let second = SegmentID()
        store.apply([
            TranscriptEvent.volatile(seg(first, "good")),
            .final(seg(first, "Good morning.", 0, 1)),
            .volatile(seg(second, "how are", 1, 2)),
        ])

        #expect(store.snapshot.lines.map(\.text) == ["Good morning.", "how are"])
        #expect(store.snapshot.lines.map(\.isFinal) == [true, false])
        #expect(store.snapshot.lines.map(\.id) == [first, second])
    }

    @Test("only the newest finalized lines are visible")
    func visibleFinalLines() {
        var store = CaptionStore(configuration: .init(historyLimit: 10, visibleFinalLines: 2))
        for index in 0..<5 {
            store.apply(.final(seg(SegmentID(), "line \(index)", Double(index), Double(index) + 1)))
        }
        #expect(store.snapshot.lines.map(\.text) == ["line 3", "line 4"])
        #expect(store.transcript.count == 5)
    }

    @Test("with zero visible final lines only the volatile line shows")
    func zeroVisibleFinals() {
        var store = CaptionStore(configuration: .init(historyLimit: 10, visibleFinalLines: 0))
        store.apply(.final(seg(SegmentID(), "done")))
        #expect(store.snapshot.isEmpty)
        let id = SegmentID()
        store.apply(.volatile(seg(id, "typing", 1, 2)))
        #expect(store.snapshot.lines.map(\.text) == ["typing"])
    }

    @Test("history is bounded: the oldest finalized segments are dropped")
    func boundedHistory() {
        var store = CaptionStore(configuration: .init(historyLimit: 3, visibleFinalLines: 1))
        let ids = (0..<5).map { _ in SegmentID() }
        for (index, id) in ids.enumerated() {
            store.apply(.final(seg(id, "s\(index)", Double(index), Double(index) + 1)))
        }
        #expect(store.transcript.map(\.text) == ["s2", "s3", "s4"])
        #expect(store.transcript.map(\.id) == Array(ids.suffix(3)))
    }

    @Test("a dropped segment cannot come back through a late event")
    func droppedSegmentStaysFinal() {
        var store = CaptionStore(configuration: .init(historyLimit: 2, visibleFinalLines: 1))
        let old = SegmentID()
        store.apply(.final(seg(old, "old")))
        store.apply(.final(seg(SegmentID(), "a", 1, 2)))
        store.apply(.final(seg(SegmentID(), "b", 2, 3)))
        #expect(!store.transcript.contains { $0.id == old })

        let outcome9 = store.apply(.final(seg(old, "old again")))
        #expect(outcome9 == .ignored)
        let outcome10 = store.apply(.volatile(seg(old, "old volatile")))
        #expect(outcome10 == .ignored)
        #expect(store.transcript.map(\.text) == ["a", "b"])
    }

    @Test("remembered final IDs are bounded too")
    func finalIDMemoryBounded() {
        var store = CaptionStore(configuration: .init(historyLimit: 1, visibleFinalLines: 1))
        let first = SegmentID()
        store.apply(.final(seg(first, "first")))
        for index in 0..<3 {
            store.apply(.final(seg(SegmentID(), "n\(index)", Double(index + 1), Double(index + 2))))
        }
        // Memory holds 2 × historyLimit IDs; the very first one has been forgotten.
        #expect(!store.isFinal(first))
        #expect(store.transcript.count == 1)
    }

    @Test("an empty volatile result clears the volatile line")
    func emptyVolatileClears() {
        var store = CaptionStore()
        let id = SegmentID()
        store.apply(.volatile(seg(id, "uh")))
        let outcome11 = store.apply(.volatile(seg(id, "   ")))
        #expect(outcome11 == .volatileCleared)
        #expect(store.snapshot.isEmpty)
        let outcome12 = store.apply(.volatile(seg(id, "")))
        #expect(outcome12 == .ignored)
    }

    @Test("an empty final removes the volatile line and adds nothing")
    func emptyFinal() {
        var store = CaptionStore()
        let id = SegmentID()
        store.apply(.volatile(seg(id, "mm")))
        let outcome13 = store.apply(.final(seg(id, "")))
        #expect(outcome13 == .volatileCleared)
        #expect(store.transcript.isEmpty)
        #expect(store.snapshot.isEmpty)
        #expect(store.isFinal(id))
        let outcome14 = store.apply(.final(seg(SegmentID(), " ")))
        #expect(outcome14 == .ignored)
    }

    @Test("text is trimmed")
    func trimsText() {
        var store = CaptionStore()
        let id = SegmentID()
        store.apply(.volatile(seg(id, "  hi ")))
        #expect(store.volatileSegments.first?.text == "hi")
        store.apply(.final(seg(id, " Hi there.\n")))
        #expect(store.transcriptText == "Hi there.")
    }

    @Test("a volatile with a new ID replaces the abandoned volatile of the same origin")
    func abandonedVolatileReplaced() {
        var store = CaptionStore()
        let abandoned = SegmentID()
        let current = SegmentID()
        store.apply(.volatile(seg(abandoned, "never finalized")))
        store.apply(.volatile(seg(current, "new phrase", 1, 2)))
        #expect(store.volatileSegments.map(\.id) == [current])
    }

    @Test("each origin keeps its own volatile line, ordered by start time")
    func volatilePerOrigin() {
        var store = CaptionStore()
        let mic = SegmentID()
        let system = SegmentID()
        store.apply(.volatile(seg(mic, "me talking", 2, 3, origin: .microphone)))
        store.apply(.volatile(seg(system, "them talking", 1, 3, origin: .system)))

        #expect(store.volatileSegments.map(\.id) == [system, mic])
        #expect(store.snapshot.lines.map(\.origin) == [.system, .microphone])

        store.apply(.final(seg(system, "Them talking.", 1, 3, origin: .system)))
        #expect(store.volatileSegments.map(\.id) == [mic])
        #expect(store.transcript.map(\.origin) == [.system])
    }

    @Test("reset clears transcript, volatile lines and final IDs")
    func reset() {
        var store = CaptionStore(configuration: .init(historyLimit: 5, visibleFinalLines: 1))
        let id = SegmentID()
        store.apply(.final(seg(id, "before")))
        store.apply(.volatile(seg(SegmentID(), "pending", 1, 2)))
        store.reset()
        #expect(store.snapshot.isEmpty)
        #expect(store.transcript.isEmpty)
        #expect(!store.isFinal(id))
        #expect(store.configuration.historyLimit == 5)
    }

    @Test("applying a sequence reports whether anything changed")
    func applySequence() {
        var store = CaptionStore()
        let id = SegmentID()
        let outcome15 = store.apply([TranscriptEvent.volatile(seg(id, "a")), .final(seg(id, "A."))])
        #expect(outcome15)
        let outcome16 = store.apply([TranscriptEvent.final(seg(id, "A again."))])
        #expect(!outcome16)
    }

    @Test("visibleFinalLines is capped at historyLimit")
    func configurationClamp() {
        let configuration = CaptionStore.Configuration(historyLimit: 2, visibleFinalLines: 9)
        #expect(configuration.visibleFinalLines == 2)
    }

    @Test("events from a fake transcriber build the expected captions")
    @MainActor
    func fakeTranscriberEvents() async throws {
        let hello = SegmentID()
        let world = SegmentID()
        let events: [TranscriptEvent] = [
            .volatile(seg(hello, "Hel", 0, 0.4)),
            .volatile(seg(hello, "Hello", 0, 0.6)),
            .volatile(seg(hello, "Hello the", 0, 0.9)),
            .final(seg(hello, "Hello there.", 0, 1.0)),
            .volatile(seg(world, "General", 1.2, 1.6)),
            .volatile(seg(hello, "Hello again", 0, 1.0)),  // late volatile for a final segment
            .final(seg(world, "General Kenobi.", 1.2, 2.0)),
            .final(seg(world, "General Kenobi!", 1.2, 2.0)),  // duplicate final
        ]
        let transcriber = ReplayTranscriber(events: events)
        let presenter = RecordingPresenter()
        var store = CaptionStore()

        for try await event in transcriber.transcribe(AsyncThrowingStream { $0.finish() }) {
            if store.apply(event).changedState {
                presenter.present(store.snapshot)
            }
        }

        #expect(store.transcript.map(\.text) == ["Hello there.", "General Kenobi."])
        #expect(store.transcript.map(\.id) == [hello, world])
        let shown = presenter.snapshots.map { $0.lines.map(\.text) }
        #expect(
            shown == [
                ["Hel"],
                ["Hello"],
                ["Hello the"],
                ["Hello there."],
                ["Hello there.", "General"],
                ["Hello there.", "General Kenobi."],
            ])
    }
}
