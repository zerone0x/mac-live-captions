import Foundation
import Testing
@testable import LiveCaptionsCore

@Suite("AudioTimeline")
struct AudioTimelineTests {
    @Test("the first chunk anchors the timeline at its start time")
    func firstChunkAnchors() {
        var timeline = AudioTimeline()
        let isNewRun1 = timeline.accept(chunkStart: 5, duration: 0.1)
        #expect(isNewRun1)
        let start1 = timeline.place(frames: 1_600, sampleRate: 16_000)
        #expect(start1 == 5)
    }

    @Test("contiguous chunks advance by output frames, not by input times")
    func contiguousChunks() {
        var timeline = AudioTimeline()
        var starts: [TimeInterval] = []
        for index in 0..<4 {
            // 48 kHz input of 0.1 s each, resampled to 16 kHz with a short first buffer.
            let isNewRun = timeline.accept(chunkStart: Double(index) * 0.1, duration: 0.1)
            #expect(isNewRun == (index == 0))
            starts.append(timeline.place(frames: index == 0 ? 1_500 : 1_600, sampleRate: 16_000))
        }
        #expect(starts == [0, 0.09375, 0.19375, 0.29375])
    }

    @Test("small jitter within the tolerance stays contiguous")
    func jitterTolerated() {
        var timeline = AudioTimeline(tolerance: 0.02)
        _ = timeline.accept(chunkStart: 0, duration: 0.1)
        let isNewRun2 = timeline.accept(chunkStart: 0.11, duration: 0.1)
        #expect(!isNewRun2)
    }

    @Test("a gap re-anchors at the new chunk")
    func gapReanchors() {
        var timeline = AudioTimeline()
        _ = timeline.accept(chunkStart: 0, duration: 0.5)
        _ = timeline.place(frames: 8_000, sampleRate: 16_000)
        let isNewRun3 = timeline.accept(chunkStart: 3, duration: 0.5)
        #expect(isNewRun3)
        let start2 = timeline.place(frames: 8_000, sampleRate: 16_000)
        #expect(start2 == 3)
        let start3 = timeline.place(frames: 8_000, sampleRate: 16_000)
        #expect(start3 == 3.5)
    }

    @Test("an overlap (time going backwards) also re-anchors")
    func overlapReanchors() {
        var timeline = AudioTimeline()
        _ = timeline.accept(chunkStart: 10, duration: 1)
        let isNewRun4 = timeline.accept(chunkStart: 2, duration: 1)
        #expect(isNewRun4)
        let start4 = timeline.place(frames: 100, sampleRate: 100)
        #expect(start4 == 2)
    }
}
