import Foundation
import Testing
@testable import LiveCaptionsCore

@Suite("Core value types")
struct ModelTests {
    @Test("AudioChunk duration and end time follow sample count and rate")
    func chunkTiming() {
        let chunk = AudioChunk(
            samples: Array(repeating: 0, count: 8_000),
            sampleRate: 16_000,
            origin: .system,
            startTime: 2
        )
        #expect(chunk.duration == 0.5)
        #expect(chunk.endTime == 2.5)
    }

    @Test("TranscriptEvent exposes its segment and finality")
    func eventAccessors() {
        let segment = TranscriptSegment(text: "hello", start: 0, end: 1, origin: .system)
        #expect(TranscriptEvent.volatile(segment).segment == segment)
        #expect(!TranscriptEvent.volatile(segment).isFinal)
        #expect(TranscriptEvent.final(segment).isFinal)
    }

    @Test("an empty snapshot means hide the overlay")
    func emptySnapshot() {
        #expect(CaptionSnapshot.empty.isEmpty)
        let line = CaptionLine(id: SegmentID(), text: "hi", origin: .system, isFinal: true)
        #expect(!CaptionSnapshot(lines: [line]).isEmpty)
    }
}
