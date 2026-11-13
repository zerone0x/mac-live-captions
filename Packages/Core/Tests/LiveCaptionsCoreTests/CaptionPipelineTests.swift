import Foundation
import Testing

@testable import LiveCaptionsCore

private func volatileEvent(_ number: Int, _ text: String) -> TranscriptEvent {
    .volatile(TranscriptSegment(id: segmentID(number), text: text, start: 0, end: 1, origin: .system))
}

private func finalEvent(_ number: Int, _ text: String) -> TranscriptEvent {
    .final(TranscriptSegment(id: segmentID(number), text: text, start: 0, end: 1, origin: .system))
}

private func snapshot(_ lines: CaptionLine...) -> CaptionSnapshot {
    CaptionSnapshot(lines: lines)
}

@Suite("CaptionUpdateThrottle")
struct CaptionUpdateThrottleTests {
    @Test("volatile updates inside the interval wait; only the newest is shown")
    func coalescesVolatileUpdates() {
        var throttle = CaptionUpdateThrottle(interval: 0.25)
        let first = snapshot(volatileLine(1, "hello"))
        #expect(throttle.submit(first, at: 10) == .presentNow(first))

        let second = snapshot(volatileLine(1, "hello there"))
        #expect(throttle.submit(second, at: 10.1) == .deferred(until: 10.25))
        let third = snapshot(volatileLine(1, "hello there my"))
        #expect(throttle.submit(third, at: 10.2) == .deferred(until: 10.25))
        #expect(throttle.pending == third)

        #expect(throttle.flush(at: 10.25) == third)
        #expect(throttle.pending == nil)
        #expect(throttle.flush(at: 10.3) == nil)

        // The interval now counts from the flush.
        let fourth = snapshot(volatileLine(1, "hello there my friend"))
        #expect(throttle.submit(fourth, at: 10.4) == .deferred(until: 10.5))
        let fifth = snapshot(volatileLine(1, "hello there my friends"))
        #expect(throttle.submit(fifth, at: 10.6) == .presentNow(fifth))
        #expect(throttle.pending == nil)
    }

    @Test("a volatile update exactly one interval after the last one is shown at once")
    func presentsAtIntervalBoundary() {
        var throttle = CaptionUpdateThrottle(interval: 0.25)
        let first = snapshot(volatileLine(1, "hello"))
        #expect(throttle.submit(first, at: 10) == .presentNow(first))
        let second = snapshot(volatileLine(1, "hello there"))
        #expect(throttle.submit(second, at: 10.25) == .presentNow(second))
        #expect(throttle.pending == nil)
    }

    @Test("new finalized text is shown at once and drops the waiting volatile update")
    func finalsAreImmediate() {
        var throttle = CaptionUpdateThrottle(interval: 0.25)
        _ = throttle.submit(snapshot(volatileLine(1, "hello")), at: 0)
        _ = throttle.submit(snapshot(volatileLine(1, "hello world")), at: 0.05)
        let final = snapshot(finalLine(1, "Hello world."))
        #expect(throttle.submit(final, at: 0.1) == .presentNow(final))
        #expect(throttle.pending == nil)

        // A volatile line after the same finals is throttled again.
        let next = snapshot(finalLine(1, "Hello world."), volatileLine(2, "how"))
        #expect(throttle.submit(next, at: 0.15) == .deferred(until: 0.35))
    }

    @Test("an empty snapshot is shown at once")
    func emptyIsImmediate() {
        var throttle = CaptionUpdateThrottle(interval: 0.25)
        _ = throttle.submit(snapshot(volatileLine(1, "hello")), at: 0)
        #expect(throttle.submit(.empty, at: 0.01) == .presentNow(.empty))
    }

    @Test("interval 0 turns throttling off")
    func zeroInterval() {
        var throttle = CaptionUpdateThrottle(interval: 0)
        let first = snapshot(volatileLine(1, "a"))
        let second = snapshot(volatileLine(1, "a b"))
        #expect(throttle.submit(first, at: 0) == .presentNow(first))
        #expect(throttle.submit(second, at: 0) == .presentNow(second))
    }
}

@Suite("CaptionPipeline")
@MainActor
struct CaptionPipelineTests {
    static func chunks(_ count: Int) -> [AudioChunk] {
        (0..<count).map { index in
            AudioChunk(
                samples: Array(repeating: 0, count: 1_600),
                sampleRate: 16_000,
                origin: .system,
                startTime: Double(index) * 0.1
            )
        }
    }

    @Test("audio source → transcriber → store → presenter, end to end with fakes")
    func endToEnd() async throws {
        let presenter = RecordingPresenter()
        let pipeline = CaptionPipeline(
            source: FakeAudioSource(chunks: Self.chunks(3)),
            transcriber: ScriptedTranscriber(words: ["hello", "live", "captions"]),
            presenter: presenter,
            throttleInterval: 0
        )
        try await pipeline.run()

        #expect(presenter.snapshots.count == 6)
        #expect(presenter.snapshots.last?.lines.map(\.text) == ["live", "captions"])
        #expect(pipeline.transcript.map(\.text) == ["hello", "live", "captions"])
    }

    @Test("volatile bursts are coalesced; finals and the last update always show")
    func throttled() async throws {
        let presenter = RecordingPresenter()
        let pipeline = CaptionPipeline(
            source: FakeAudioSource(chunks: Self.chunks(1)),
            transcriber: ReplayTranscriber(events: [
                volatileEvent(1, "the"),
                volatileEvent(1, "the quick"),
                volatileEvent(1, "the quick brown"),
                finalEvent(1, "The quick brown fox."),
                volatileEvent(2, "jumps"),
                volatileEvent(2, "jumps over"),
            ]),
            presenter: presenter,
            throttleInterval: 0.25,
            now: { 0 },
            sleep: { _ in try? await Task.sleep(for: .seconds(60)) }
        )
        try await pipeline.run()

        let shown = presenter.snapshots.map { $0.lines.map(\.text) }
        #expect(shown.count == 3)
        #expect(shown.first == ["the"])
        #expect(shown.dropFirst().first == ["The quick brown fox."])
        // The waiting volatile update is flushed when the session ends.
        #expect(shown.last == ["The quick brown fox.", "jumps over"])
    }

    @Test("mid-session, a waiting volatile update is shown when the interval ends")
    func timerFlushMidSession() async throws {
        let source = LiveFakeAudioSource()
        let transcriber = ControlledTranscriber()
        let presenter = RecordingPresenter()
        let clock = ManualClock()
        let sleeper = ManualSleeper()
        let pipeline = CaptionPipeline(
            source: source,
            transcriber: transcriber,
            presenter: presenter,
            throttleInterval: 0.25,
            now: { clock.now },
            sleep: { seconds in await sleeper.sleep(seconds) }
        )
        let run = Task { try await pipeline.run() }
        try await waitUntil { source.isStarted && transcriber.isTranscribing }

        clock.now = 10
        transcriber.send(volatileEvent(1, "hello"))
        try await waitUntil { presenter.snapshots.count == 1 }

        // Inside the interval: waits for the timer.
        clock.now = 10.1
        transcriber.send(volatileEvent(1, "hello there"))
        try await waitUntil { sleeper.sleeping == 1 }
        #expect(sleeper.requestedDelays.count == 1)
        #expect(abs((sleeper.requestedDelays.first ?? 0) - 0.15) < 1e-9)
        #expect(presenter.snapshots.count == 1)

        // The interval ends while the session still runs.
        clock.now = 10.25
        sleeper.wakeAll()
        try await waitUntil { presenter.snapshots.count == 2 }
        #expect(presenter.snapshots.last?.lines.map(\.text) == ["hello there"])
        #expect(source.isStarted)

        // The next volatile update is throttled again, from the flush.
        clock.now = 10.3
        transcriber.send(volatileEvent(1, "hello there friend"))
        try await waitUntil { sleeper.sleeping == 1 }
        #expect(abs((sleeper.requestedDelays.last ?? 0) - 0.2) < 1e-9)
        #expect(presenter.snapshots.count == 2)

        await source.stop()
        try await run.value
        // Stopping flushes it.
        #expect(presenter.snapshots.count == 3)
        #expect(presenter.snapshots.last?.lines.map(\.text) == ["hello there friend"])
    }

    @Test("a denied permission is thrown from run()")
    func permissionDenied() async {
        let pipeline = CaptionPipeline(
            source: FailingAudioSource(error: .permissionDenied(.system)),
            transcriber: ScriptedTranscriber(words: []),
            presenter: RecordingPresenter()
        )
        await #expect(throws: AudioCaptureError.permissionDenied(.system)) {
            try await pipeline.run()
        }
    }

    @Test("a missing speech model is thrown from run()")
    func modelMissing() async {
        let pipeline = CaptionPipeline(
            source: FakeAudioSource(chunks: Self.chunks(2)),
            transcriber: FailingTranscriber(error: .assetsNotReady(.notInstalled)),
            presenter: RecordingPresenter()
        )
        await #expect(throws: TranscriptionError.assetsNotReady(.notInstalled)) {
            try await pipeline.run()
        }
    }

    @Test("a capture failure mid-session is thrown from run()")
    func captureFailure() async throws {
        let source = LiveFakeAudioSource()
        let pipeline = CaptionPipeline(
            source: source,
            transcriber: ScriptedTranscriber(words: ["one"]),
            presenter: RecordingPresenter(),
            throttleInterval: 0
        )
        let run = Task { try await pipeline.run() }
        try await waitUntil { source.isStarted }
        source.fail(AudioCaptureError.interrupted("device gone"))
        await #expect(throws: AudioCaptureError.interrupted("device gone")) {
            try await run.value
        }
    }

    @Test("stopping the source ends run() normally, after the last caption")
    func stopEndsRun() async throws {
        let source = LiveFakeAudioSource()
        let presenter = RecordingPresenter()
        let pipeline = CaptionPipeline(
            source: source,
            transcriber: ScriptedTranscriber(words: ["one", "two"]),
            presenter: presenter,
            throttleInterval: 0
        )
        let run = Task { try await pipeline.run() }
        try await waitUntil { source.isStarted }
        for chunk in Self.chunks(2) {
            source.yield(chunk)
        }
        try await waitUntil { presenter.snapshots.count == 4 }
        await source.stop()
        try await run.value
        #expect(presenter.snapshots.last?.lines.map(\.text) == ["one", "two"])
        #expect(source.stops == 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("timed out waiting for a condition")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
