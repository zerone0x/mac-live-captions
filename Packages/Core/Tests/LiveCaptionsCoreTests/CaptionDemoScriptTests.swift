import Foundation
import Testing

@testable import LiveCaptionsCore

@Suite("Caption demo script")
struct CaptionDemoScriptTests {
    let script = CaptionDemoScript.english

    @Test("every utterance is revised while volatile and then finalized")
    func revisionsThenFinal() {
        var volatileSeen: [SegmentID: [String]] = [:]
        var finalized: [SegmentID] = []
        for step in script.steps {
            for line in step.snapshot.lines {
                if line.isFinal {
                    if !finalized.contains(line.id) { finalized.append(line.id) }
                } else {
                    #expect(!finalized.contains(line.id), "volatile after final for \(line.id)")
                    volatileSeen[line.id, default: []].append(line.text)
                }
            }
        }
        #expect(finalized.count == 7)
        #expect(Set(volatileSeen.keys) == Set(finalized))
        #expect(volatileSeen.values.allSatisfy { $0.count >= 3 })
        // At least one hypothesis is corrected, not just extended.
        let corrected = volatileSeen.values.contains { texts in
            zip(texts, texts.dropFirst()).contains { !$1.hasPrefix($0) }
        }
        #expect(corrected)
        #expect(script.steps.last?.snapshot.lines.allSatisfy(\.isFinal) == true)
    }

    @Test("is English text only and runs for under a minute")
    func englishAndShort() {
        let texts = script.steps.flatMap(\.snapshot.lines).map(\.text)
        #expect(texts.allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })
        #expect(script.duration > 10)
        #expect(script.duration < 60)
        #expect(script.steps.allSatisfy { $0.delay >= 0 })
    }

    @Test("played through the composer it follows the layout rules, collapses once and ends visible")
    func playsThroughComposer() {
        var composer = CaptionComposer()
        var previous: CaptionFrame?
        var now = 0.0
        var collapses = 0
        for step in script.steps {
            if previous != nil, !composer.isExpanded(at: now + step.delay) {
                collapses += 1
            }
            now += step.delay
            let frame = composer.apply(step.snapshot, at: now)
            #expect(layoutViolations(previous: previous, current: frame).isEmpty, "at \(now)s")
            #expect(composer.isExpanded(at: now))
            previous = frame
        }
        #expect(collapses == 1)
        #expect(
            composer.frame.lines.map(\.text).joined(separator: " ")
                == "And it comes back as soon as someone speaks again.")
    }
}
