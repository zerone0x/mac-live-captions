import Foundation
import Testing

@testable import LiveCaptionsCore

/// Deterministic random numbers (SplitMix64), so a failing sequence repeats.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A stand-in for `AVAudioConverter`: emits the output frames the input has
/// covered so far, minus a fixed latency at the start of each run, so the
/// frame counts it reports are uneven like a real resampler's.
private struct FakeResampler {
    let outputRate: Int
    let latency: Int
    private var inputRate: Double?
    private var inputFrames: Int64 = 0
    private var emitted: Int64 = 0

    init(outputRate: Int, latency: Int = 20) {
        self.outputRate = outputRate
        self.latency = latency
    }

    mutating func reset() {
        inputFrames = 0
        emitted = 0
    }

    mutating func convert(frames: Int, rate: Double) -> Int {
        if inputRate != rate {
            inputRate = rate
            reset()
        }
        inputFrames += Int64(frames)
        let covered = Int64((Double(inputFrames) * Double(outputRate) / rate).rounded(.down)) - Int64(latency)
        let out = max(0, covered - emitted)
        emitted += out
        return Int(out)
    }
}

/// One buffer as the analyzer would get it.
private struct FedInput: Equatable {
    let start: Int64
    let frames: Int
    let newRun: Bool
}

/// The adapter's path (timeline → resampler → guard) for a list of
/// `(start seconds, frames, input rate)` chunks.
private func feed(
    _ chunks: [(start: TimeInterval, frames: Int, rate: Double)],
    outputRate: Int = 16_000,
    tolerance: TimeInterval = 0.02
) -> (inputs: [FedInput], guard: MonotonicInputGuard) {
    var timeline = AudioTimeline(sampleRate: outputRate, tolerance: tolerance)
    var resampler = FakeResampler(outputRate: outputRate)
    var gate = MonotonicInputGuard()
    var inputs: [FedInput] = []
    // A run whose first chunks give no output yet still starts a run.
    var runPending = false
    for chunk in chunks {
        let accepted = timeline.accept(chunkStart: chunk.start, duration: Double(chunk.frames) / chunk.rate)
        if accepted { resampler.reset() }
        runPending = runPending || accepted
        let newRun = runPending
        let frames =
            chunk.rate == Double(outputRate) ? chunk.frames : resampler.convert(frames: chunk.frames, rate: chunk.rate)
        guard frames > 0 else { continue }
        let proposed = timeline.place(frames: frames)
        if let start = gate.admit(start: proposed, frames: frames) {
            inputs.append(FedInput(start: start, frames: frames, newRun: newRun))
            runPending = false
        }
    }
    return (inputs, gate)
}

/// Every input starts at or after the end of the one before; inputs of one
/// contiguous run follow each other sample-exactly.
private func expectMonotonic(_ inputs: [FedInput], sourceLocation: SourceLocation = #_sourceLocation) {
    for (previous, next) in zip(inputs, inputs.dropFirst()) {
        let previousEnd = previous.start + Int64(previous.frames)
        #expect(next.start >= previousEnd, "overlap: \(previous) then \(next)", sourceLocation: sourceLocation)
        if !next.newRun {
            #expect(
                next.start == previousEnd, "gap inside a run: \(previous) then \(next)", sourceLocation: sourceLocation)
        }
    }
}

/// `count` chunks of `frames` frames at `rate`, stamped the way
/// `AudioChunkAssembler` stamps them (frame count / rate, as a Double).
private func assembled(count: Int, frames: Int, rate: Double, offset: Int64 = 0) -> [(TimeInterval, Int, Double)] {
    (0..<count).map { index in
        (Double(offset + Int64(index) * Int64(frames)) / rate, frames, rate)
    }
}

@Suite("AudioTimeline", .timeLimit(.minutes(1)))
struct AudioTimelineTests {
    @Test("the first chunk anchors the timeline at its start frame")
    func firstChunkAnchors() {
        var timeline = AudioTimeline(sampleRate: 16_000)
        let result1 = timeline.accept(chunkStart: 5, duration: 0.1)
        #expect(result1)
        let result2 = timeline.place(frames: 1_600)
        #expect(result2 == 80_000)
        #expect(timeline.placedEnd == 81_600)
    }

    @Test("contiguous chunks advance by output frames, not by input times")
    func contiguousChunks() {
        var timeline = AudioTimeline(sampleRate: 16_000)
        var starts: [Int64] = []
        for index in 0..<4 {
            // 48 kHz input of 0.1 s each, resampled to 16 kHz with a short first buffer.
            let isNewRun = timeline.accept(chunkStart: Double(index) * 0.1, duration: 0.1)
            #expect(isNewRun == (index == 0))
            starts.append(timeline.place(frames: index == 0 ? 1_500 : 1_600))
        }
        #expect(starts == [0, 1_500, 3_100, 4_700])
    }

    // Issue #48: on main the start of the chunk at 32.3 s was the Double
    // 516800 / 16000, which is one ulp below 32.3; CMTime(seconds:) turned it
    // into frame 516799, one sample before the previous input's end.
    @Test("the chunk at 32.3 s starts exactly at frame 516800")
    func noDoubleRoundingAtKnownBadFrame() {
        let (inputs, gate) = feed(assembled(count: 324, frames: 1_600, rate: 16_000).map { ($0.0, $0.1, $0.2) })
        #expect(inputs[323].start == 516_800)
        #expect(Double(inputs[323].start) / 16_000 == 32.3)
        expectMonotonic(inputs)
        #expect(gate.shiftedInputs == 0)
    }

    @Test("an hour of 100 ms chunks at 16 kHz is sample-exact")
    func oneHourSession() {
        let chunks = assembled(count: 36_000, frames: 1_600, rate: 16_000).map { ($0.0, $0.1, $0.2) }
        let (inputs, gate) = feed(chunks)
        #expect(inputs.count == 36_000)
        for (index, input) in inputs.enumerated() {
            if input.start != Int64(index) * 1_600 {
                Issue.record("chunk \(index) starts at \(input.start), expected \(index * 1_600)")
                break
            }
        }
        expectMonotonic(inputs)
        #expect(inputs.filter(\.newRun).count == 1)
        #expect(gate.shiftedInputs == 0)
    }

    @Test("48 kHz and 44.1 kHz input resampled to 16 kHz stays contiguous", arguments: [48_000.0, 44_100.0])
    func resampledInput(rate: Double) {
        let frames = Int(rate / 10)
        let chunks = assembled(count: 6_000, frames: frames, rate: rate).map { ($0.0, $0.1, $0.2) }
        let (inputs, gate) = feed(chunks)
        expectMonotonic(inputs)
        #expect(inputs.filter(\.newRun).count == 1)
        #expect(gate.shiftedInputs == 0)
        let total = inputs.reduce(0) { $0 + $1.frames }
        // 600 s of audio, minus the resampler's latency.
        #expect(abs(total - 600 * 16_000) <= 40)
    }

    @Test("jitter within the tolerance stays contiguous and sample-exact")
    func jitterTolerated() {
        var generator = SeededGenerator(seed: 48)
        var chunks: [(start: TimeInterval, frames: Int, rate: Double)] = []
        for index in 0..<2_000 {
            // Consecutive chunks differ by at most 18 ms, inside the 20 ms tolerance.
            let jitter = Double.random(in: -0.009...0.009, using: &generator)
            chunks.append((Double(index) * 0.1 + jitter, 1_600, 16_000))
        }
        let (inputs, gate) = feed(chunks)
        #expect(inputs.filter(\.newRun).count == 1)
        expectMonotonic(inputs)
        #expect(gate.shiftedInputs == 0)
    }

    @Test("a mismatch of exactly the tolerance is still contiguous")
    func mismatchAtTolerance() {
        var timeline = AudioTimeline(sampleRate: 16_000, tolerance: 0.25)
        let result3 = timeline.accept(chunkStart: 0, duration: 1)
        #expect(result3)
        _ = timeline.place(frames: 16_000)
        // Expected 1.0, got 1.25: off by exactly the tolerance.
        let result4 = timeline.accept(chunkStart: 1.25, duration: 1)
        #expect(!result4)
        // Expected 2.25, got 2.0: the same mismatch the other way round.
        let result5 = timeline.accept(chunkStart: 2.0, duration: 1)
        #expect(!result5)
        // Expected 3.0, got 3.5: beyond the tolerance.
        let result6 = timeline.accept(chunkStart: 3.5, duration: 1)
        #expect(result6)
    }

    @Test("gaps just below and just above the tolerance")
    func gapsAroundTolerance() {
        // 19 ms gap: contiguous, the audio closes up.
        let below = feed([(0, 1_600, 16_000), (0.119, 1_600, 16_000)])
        #expect(below.inputs.map(\.start) == [0, 1_600])
        #expect(below.inputs.map(\.newRun) == [true, false])
        // 21 ms gap: a new run at the chunk's own frame.
        let above = feed([(0, 1_600, 16_000), (0.121, 1_600, 16_000)])
        #expect(above.inputs.map(\.start) == [0, 1_936])
        #expect(above.inputs.map(\.newRun) == [true, true])
        expectMonotonic(above.inputs)
    }

    @Test("a gap re-anchors at the new chunk")
    func gapReanchors() {
        var timeline = AudioTimeline(sampleRate: 16_000)
        _ = timeline.accept(chunkStart: 0, duration: 0.5)
        _ = timeline.place(frames: 8_000)
        let result7 = timeline.accept(chunkStart: 3, duration: 0.5)
        #expect(result7)
        let result8 = timeline.place(frames: 8_000)
        #expect(result8 == 48_000)
        let result9 = timeline.place(frames: 8_000)
        #expect(result9 == 56_000)
    }

    @Test("a non-integer anchor is rounded once; later buffers follow sample-exactly")
    func nonIntegerAnchor() {
        // 0.123456789 s = 1975.31 frames; 7.00003125 s = 112000.5 frames.
        let start = 0.123_456_789
        let chunks = (0..<1_000).map { (start + Double($0) * 0.1, 1_600, 16_000.0) }
        let (inputs, _) = feed(chunks)
        let starts = inputs.map(\.start)
        #expect(starts.count == 1_000)
        #expect(starts.first == 1_975)
        #expect(starts.last == Int64(1_975 + 999 * 1_600))
        expectMonotonic(inputs)

        var timeline = AudioTimeline(sampleRate: 16_000)
        _ = timeline.accept(chunkStart: 7.000_031_25, duration: 0.1)
        let result10 = timeline.place(frames: 3)
        #expect(result10 == 112_001)
    }

    @Test("an overlap (time going backwards) re-anchors at the end of placed audio")
    func overlapReanchors() {
        var timeline = AudioTimeline(sampleRate: 100)
        _ = timeline.accept(chunkStart: 10, duration: 1)
        let result11 = timeline.place(frames: 100)
        #expect(result11 == 1_000)
        let result12 = timeline.accept(chunkStart: 2, duration: 1)
        #expect(result12)
        // Starting at 2 s would be before input already given to the analyzer.
        let result13 = timeline.place(frames: 100)
        #expect(result13 == 1_100)
        // The run stays contiguous from the shifted anchor.
        let result14 = timeline.accept(chunkStart: 3, duration: 1)
        #expect(!result14)
        let result15 = timeline.place(frames: 100)
        #expect(result15 == 1_200)
    }

    @Test("an overlap of less than one frame after a re-anchor never lands a sample early")
    func subFrameOverlap() {
        // The second run starts a fraction of a frame before the end of the
        // first; rounding it to the nearest frame would go one frame back.
        // Tolerance 0 makes every mismatch a new run.
        let chunks: [(start: TimeInterval, frames: Int, rate: Double)] = [
            (0, 1_600, 16_000), (0.099_97, 1_600, 16_000), (0.199_999, 1_600, 16_000),
        ]
        let (inputs, gate) = feed(chunks, tolerance: 0)
        #expect(inputs.map(\.start) == [0, 1_600, 3_200])
        #expect(inputs.map(\.newRun) == [true, true, true])
        expectMonotonic(inputs)
        #expect(gate.shiftedInputs == 0)
    }

    @Test("an overlap before any audio was placed anchors at the chunk")
    func overlapBeforePlacement() {
        var timeline = AudioTimeline(sampleRate: 100)
        _ = timeline.accept(chunkStart: 10, duration: 1)
        _ = timeline.accept(chunkStart: 2, duration: 1)
        let result16 = timeline.place(frames: 100)
        #expect(result16 == 200)
    }

    @Test("randomized sessions never feed an overlapping input", arguments: [1, 7, 48, 2_026, 65_535] as [UInt64])
    func randomizedSessions(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let rates: [Double] = [16_000, 44_100, 48_000]
        var chunks: [(start: TimeInterval, frames: Int, rate: Double)] = []
        var time = Double.random(in: 0...3, using: &generator)
        var rate = rates.randomElement(using: &generator)!
        for _ in 0..<5_000 {
            switch Int.random(in: 0..<100, using: &generator) {
            case 0..<3: rate = rates.randomElement(using: &generator)!  // device switch
            case 3..<6: time += Double.random(in: 0.0...2.0, using: &generator)  // pause / sleep
            case 6..<9: time -= Double.random(in: 0.0...0.5, using: &generator)  // clock steps back
            default: break
            }
            let frames = Int.random(in: 1...Int(rate / 5), using: &generator)
            let jitter = Double.random(in: -0.025...0.025, using: &generator)
            chunks.append((max(0, time + jitter), frames, rate))
            time += Double(frames) / rate
        }
        let (inputs, gate) = feed(chunks)
        #expect(!inputs.isEmpty)
        expectMonotonic(inputs)
        // The timeline alone keeps order; the guard is only a backstop.
        #expect(gate.shiftedInputs == 0)
    }
}

@Suite("SampleTime")
struct SampleTimeTests {
    @Test("seconds round to the nearest frame and never go negative")
    func frames() {
        #expect(SampleTime.frame(atSeconds: 32.3, sampleRate: 16_000) == 516_800)
        #expect(SampleTime.frame(atSeconds: 516_800.0 / 16_000, sampleRate: 16_000) == 516_800)
        #expect(SampleTime.frame(atSeconds: 0.000_031, sampleRate: 16_000) == 0)
        #expect(SampleTime.frame(atSeconds: 0.000_032, sampleRate: 16_000) == 1)
        #expect(SampleTime.frame(atSeconds: -1, sampleRate: 16_000) == 0)
        #expect(SampleTime.frame(atSeconds: .nan, sampleRate: 16_000) == 0)
        #expect(SampleTime.frame(atSeconds: .infinity, sampleRate: 16_000) == 0)
        #expect(SampleTime.seconds(ofFrame: 24_000, sampleRate: 16_000) == 1.5)
    }
}

@Suite("MonotonicInputGuard")
struct MonotonicInputGuardTests {
    @Test("inputs in order pass unchanged, gaps are kept")
    func inOrder() {
        var gate = MonotonicInputGuard()
        let result17 = gate.admit(start: 0, frames: 1_600)
        #expect(result17 == 0)
        let result18 = gate.admit(start: 1_600, frames: 1_600)
        #expect(result18 == 1_600)
        let result19 = gate.admit(start: 10_000, frames: 10)
        #expect(result19 == 10_000)
        #expect(gate.end == 10_010)
        #expect(gate.shiftedInputs == 0)
    }

    @Test("an overlapping start moves to the previous end, using the real frame count")
    func overlapShifted() {
        var gate = MonotonicInputGuard()
        let result20 = gate.admit(start: 0, frames: 1_601)
        #expect(result20 == 0)
        // One sample early (the issue #48 failure) and a lot early.
        let result21 = gate.admit(start: 1_600, frames: 1_600)
        #expect(result21 == 1_601)
        let result22 = gate.admit(start: 5, frames: 100)
        #expect(result22 == 3_201)
        #expect(gate.shiftedInputs == 2)
        #expect(gate.end == 3_301)
    }

    @Test("empty inputs are not fed and do not move the end")
    func emptyInput() {
        var gate = MonotonicInputGuard()
        let result23 = gate.admit(start: 0, frames: 0)
        #expect(result23 == nil)
        #expect(gate.end == nil)
        let result24 = gate.admit(start: -5, frames: 3)
        #expect(result24 == 0)
    }
}

@Suite("AnalyzerRestartBudget")
struct AnalyzerRestartBudgetTests {
    @Test("allows a bounded number of restarts per window")
    func bounded() {
        var budget = AnalyzerRestartBudget(maxRestarts: 3, window: 300)
        let result25 = budget.requestRestart(at: 10)
        #expect(result25)
        let result26 = budget.requestRestart(at: 11)
        #expect(result26)
        let result27 = budget.requestRestart(at: 12)
        #expect(result27)
        // A failure that repeats at once does not loop.
        let result28 = budget.requestRestart(at: 13)
        #expect(!result28)
        let result29 = budget.requestRestart(at: 309)
        #expect(!result29)
        // The first restart left the window.
        let result30 = budget.requestRestart(at: 310)
        #expect(result30)
        #expect(budget.recentRestarts == 3)
    }

    @Test("a zero budget never restarts")
    func zero() {
        var budget = AnalyzerRestartBudget(maxRestarts: 0)
        let result31 = budget.requestRestart(at: 0)
        #expect(!result31)
    }
}
