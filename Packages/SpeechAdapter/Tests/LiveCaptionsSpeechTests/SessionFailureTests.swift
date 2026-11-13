import Foundation
import LiveCaptionsCore
import Testing

@testable import LiveCaptionsSpeech

private struct InjectedFailure: Error {}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}

/// The session plumbing of `SpeechAnalyzerTranscriber` (`eventStream` plus
/// `resultsTask`) with a fake results consumer, since the real analyzer is not
/// available on CI.
@Suite("SpeechAnalyzerTranscriber session")
struct SessionFailureTests {
    @Test("a results failure ends the event stream at once and cancels the feed loop")
    func resultsFailureSurfacesImmediately() async throws {
        // Live audio that never ends on its own.
        let (audio, audioInput) = AsyncThrowingStream.makeStream(of: AudioChunk.self)
        let feedCancelled = Flag()
        // Safety net so a regression fails the test instead of hanging it.
        let safety = Task {
            try await Task.sleep(for: .seconds(10))
            audioInput.finish()
        }
        defer { safety.cancel() }

        let segment = TranscriptSegment(text: "hello", start: 0, end: 0.5, origin: .system)
        let stream = SpeechAnalyzerTranscriber.eventStream { continuation in
            let results = SpeechAnalyzerTranscriber.resultsTask(continuation: continuation) {
                continuation.yield(.volatile(segment))
                try await Task.sleep(for: .milliseconds(50))
                throw InjectedFailure()
            }
            do {
                // Same shape as the real feed loop: feed audio until it ends,
                // then wait for the results.
                for try await _ in audio {}
                try Task.checkCancellation()
                try await results.value
            } catch {
                if Task.isCancelled { await feedCancelled.set() }
                results.cancel()
                throw error
            }
        }

        let clock = ContinuousClock()
        let started = clock.now
        var events: [TranscriptEvent] = []
        var thrown: (any Error)?
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch {
            thrown = error
        }
        let elapsed = clock.now - started

        #expect(thrown is InjectedFailure)
        #expect(events == [.volatile(segment)])
        #expect(elapsed < .seconds(5))

        var cancelled = false
        for _ in 0..<200 where !cancelled {
            cancelled = await feedCancelled.isSet
            if !cancelled { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(cancelled)
    }

    @Test("cancelling the results task from the session does not replace the session's error")
    func cancelledResultsDoNotFinishTheStream() async throws {
        let stream = SpeechAnalyzerTranscriber.eventStream { continuation in
            let results = SpeechAnalyzerTranscriber.resultsTask(continuation: continuation) {
                try await Task.sleep(for: .seconds(60))
            }
            results.cancel()
            _ = await results.result
            throw InjectedFailure()
        }
        var thrown: (any Error)?
        do {
            for try await _ in stream {}
        } catch {
            thrown = error
        }
        #expect(thrown is InjectedFailure)
    }
}
