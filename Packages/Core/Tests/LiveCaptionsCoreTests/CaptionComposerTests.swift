import Foundation
import Testing
@testable import LiveCaptionsCore

/// Deterministic segment IDs for readable tests.
func segmentID(_ number: Int) -> SegmentID {
    SegmentID(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!)
}

func volatileLine(_ number: Int, _ text: String) -> CaptionLine {
    CaptionLine(id: segmentID(number), text: text, origin: .system, isFinal: false)
}

func finalLine(_ number: Int, _ text: String) -> CaptionLine {
    CaptionLine(id: segmentID(number), text: text, origin: .system, isFinal: true)
}

/// Checks the layout rules for one frame and against the previous frame.
/// Returns the problems found, empty when the frame is fine.
func layoutViolations(
    previous: CaptionFrame?,
    current: CaptionFrame,
    configuration: CaptionComposer.Configuration = .english
) -> [String] {
    var problems: [String] = []
    if current.lines.count > configuration.maxLines {
        problems.append("\(current.lines.count) lines")
    }
    for line in current.lines where line.text.count > configuration.maxLineLength {
        problems.append("line too long: \(line.text)")
    }
    // Volatile text only at the end: after the first volatile part, no final text.
    if let firstVolatile = current.lines.firstIndex(where: \.hasVolatileText) {
        for line in current.lines[(firstVolatile + 1)...] where !line.finalText.isEmpty {
            problems.append("final text after volatile text: \(line.text)")
        }
    }
    // Finalized text never changes: a line that stays on screen may only gain
    // final words at its end.
    if let previous {
        for old in previous.lines {
            guard let new = current.lines.first(where: { $0.id == old.id }) else { continue }
            if !new.finalText.hasPrefix(old.finalText) {
                problems.append("final text changed on line \(old.id): '\(old.finalText)' -> '\(new.finalText)'")
            }
        }
        // Lines never scroll back down past what was already on top, unless all
        // the text above went away.
        if let oldTop = previous.lines.first?.id, let newTop = current.lines.first?.id,
           newTop < oldTop, current.lines.last.map({ $0.id >= oldTop }) == true {
            problems.append("scrolled back from line \(oldTop) to \(newTop)")
        }
    }
    return problems
}

@Suite("Caption composer")
struct CaptionComposerTests {
    @Test("volatile text is shown lighter after final text on the same line")
    func finalThenVolatile() {
        var composer = CaptionComposer()
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "Hello there."), volatileLine(2, "How are")]), at: 0)
        #expect(composer.frame.lines == [
            CaptionDisplayLine(id: 0, finalText: "Hello there.", volatileText: " How are"),
        ])
        #expect(composer.frame.lines[0].text == "Hello there. How are")
    }

    @Test("finalizing replaces the volatile tail without moving earlier text")
    func finalization() {
        var composer = CaptionComposer()
        var previous: CaptionFrame?
        let snapshots = [
            CaptionSnapshot(lines: [volatileLine(1, "Good")]),
            CaptionSnapshot(lines: [volatileLine(1, "Good mourning")]),
            CaptionSnapshot(lines: [volatileLine(1, "Good morning every one")]),
            CaptionSnapshot(lines: [finalLine(1, "Good morning, everyone.")]),
            CaptionSnapshot(lines: [finalLine(1, "Good morning, everyone."), volatileLine(2, "Let's get")]),
            CaptionSnapshot(lines: [finalLine(1, "Good morning, everyone."), finalLine(2, "Let's get started.")]),
        ]
        for (time, snapshot) in snapshots.enumerated() {
            let frame = composer.apply(snapshot, at: Double(time))
            #expect(layoutViolations(previous: previous, current: frame).isEmpty)
            previous = frame
        }
        #expect(composer.frame.lines.map(\.text) == ["Good morning, everyone. Let's get started."])
        #expect(composer.frame.lines.allSatisfy { !$0.hasVolatileText })
    }

    @Test("final segments repeated by later snapshots are not duplicated")
    func repeatedFinals() {
        var composer = CaptionComposer()
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "One.")]), at: 0)
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "One."), finalLine(2, "Two.")]), at: 1)
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "One."), finalLine(2, "Two."), volatileLine(3, "Three")]), at: 2)
        #expect(composer.frame.lines.map(\.text) == ["One. Two. Three"])
    }

    @Test("shows at most two lines of 42 characters and scrolls up")
    func scrolling() {
        var composer = CaptionComposer()
        var previous: CaptionFrame?
        for index in 1...60 {
            let frame = composer.apply(
                CaptionSnapshot(lines: [finalLine(index, "word\(index) and some more text")]),
                at: Double(index) * 0.5
            )
            #expect(layoutViolations(previous: previous, current: frame).isEmpty)
            previous = frame
        }
        #expect(composer.frame.lines.count == 2)
        #expect(composer.frame.lines.map(\.text).joined(separator: " ").hasSuffix("word60 and some more text"))
        #expect(composer.frame.lines.map(\.id) == [composer.frame.lines[0].id, composer.frame.lines[0].id + 1])
        #expect(composer.frame.lines[0].id > 30)
    }

    @Test("a shorter revision does not scroll the view back down")
    func noScrollBack() {
        var composer = CaptionComposer()
        let first = String(repeating: "a", count: 40)
        composer.apply(CaptionSnapshot(lines: [
            finalLine(1, first),
            volatileLine(2, "bbbbbbbbbbbbbbbbbbbb cccccccccccccccccccc dddddddddddddddddddd eeeeeeeeeeeeeeeeeeee"),
        ]), at: 0)
        #expect(composer.frame.lines.map(\.id) == [1, 2])

        composer.apply(CaptionSnapshot(lines: [finalLine(1, first), volatileLine(2, "bbbbbbbbbbbbbbbbbbbb")]), at: 1)
        #expect(composer.frame.lines.map(\.id) == [1])
        #expect(composer.frame.lines[0].volatileText == "bbbbbbbbbbbbbbbbbbbb")

        // If the text shrinks above the top line, the view moves back to it.
        composer.apply(CaptionSnapshot(lines: [finalLine(1, first), volatileLine(2, "b")]), at: 2)
        #expect(composer.frame.lines.map(\.text) == [first + " b"])
        #expect(composer.frame.lines.map(\.id) == [0])
    }

    @Test("collapses after the idle timeout and only new text resets the timer")
    func idleCollapse() {
        var composer = CaptionComposer(configuration: .init(maxLines: 2, maxLineLength: 42, idleTimeout: 5))
        #expect(composer.collapseDeadline == nil)
        #expect(!composer.isExpanded(at: 0))

        composer.apply(CaptionSnapshot(lines: [volatileLine(1, "Hello")]), at: 10)
        #expect(composer.collapseDeadline == 15)
        #expect(composer.isExpanded(at: 14.9))
        #expect(!composer.isExpanded(at: 15))

        // Same text again: not activity, deadline unchanged.
        composer.apply(CaptionSnapshot(lines: [volatileLine(1, "Hello")]), at: 12)
        #expect(composer.collapseDeadline == 15)

        composer.apply(CaptionSnapshot(lines: [volatileLine(1, "Hello world")]), at: 13)
        #expect(composer.collapseDeadline == 18)
    }

    @Test("text after an idle collapse starts on a fresh line")
    func freshParagraphAfterIdle() {
        var composer = CaptionComposer(configuration: .init(maxLines: 2, maxLineLength: 42, idleTimeout: 5))
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "Old sentence.")]), at: 0)
        let oldID = composer.frame.lines[0].id

        // The store still repeats the old final segment; it must not come back.
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "Old sentence."), volatileLine(2, "New")]), at: 20)
        #expect(composer.frame.lines.map(\.text) == ["New"])
        #expect(composer.frame.lines[0].id > oldID)
        #expect(composer.isExpanded(at: 21))
    }

    @Test("an empty snapshot hides everything")
    func emptySnapshot() {
        var composer = CaptionComposer()
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "Hello.")]), at: 0)
        composer.apply(.empty, at: 1)
        #expect(composer.frame.isEmpty)
        #expect(composer.collapseDeadline == nil)
        #expect(!composer.isExpanded(at: 1))

        // The same segment may be shown again after a reset.
        composer.apply(CaptionSnapshot(lines: [finalLine(1, "Hello.")]), at: 2)
        #expect(composer.frame.lines.map(\.text) == ["Hello."])
    }

    @Test("whitespace-only text shows nothing")
    func blankText() {
        var composer = CaptionComposer()
        composer.apply(CaptionSnapshot(lines: [volatileLine(1, "   ")]), at: 0)
        #expect(composer.frame.isEmpty)
        #expect(!composer.isExpanded(at: 0))
    }

    @Test("finalized text never changes on screen while volatile text is revised")
    func stabilityUnderRevisions() {
        // Volatile revisions that grow, shrink and wrap differently.
        let revisions = [
            "so the",
            "so the quarterly numbers look",
            "so the quarterly numbers look pretty strong across every single region we",
            "so the quarterly numbers",
            "so the quarterly numbers look pretty strong across every region",
        ]
        var composer = CaptionComposer()
        var previous: CaptionFrame?
        var time = 0.0
        for sentence in 1...6 {
            let earlier = (max(1, sentence - 2)..<sentence).map { finalLine($0, "Sentence \($0) is finished now.") }
            for revision in revisions {
                time += 0.3
                let frame = composer.apply(CaptionSnapshot(lines: earlier + [volatileLine(sentence, revision)]), at: time)
                #expect(layoutViolations(previous: previous, current: frame).isEmpty)
                previous = frame
            }
            time += 0.3
            let frame = composer.apply(
                CaptionSnapshot(lines: earlier + [finalLine(sentence, "Sentence \(sentence) is finished now.")]),
                at: time
            )
            #expect(layoutViolations(previous: previous, current: frame).isEmpty)
            previous = frame
        }
    }
}
