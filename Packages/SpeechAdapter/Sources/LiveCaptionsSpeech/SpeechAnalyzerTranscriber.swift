@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import LiveCaptionsCore
import Speech

/// On-device streaming transcription with `SpeechAnalyzer` + `SpeechTranscriber`.
///
/// One `transcribe(_:)` call is one analysis session:
///
/// 1. Resolve en-US and check the model with `AssetInventory`. The model is
///    not downloaded here: if it is missing the stream throws
///    `TranscriptionError.assetsNotReady` (install it with `SystemSpeechAssets`).
/// 2. Convert each `AudioChunk` to the analyzer's best available format and
///    feed it as `AnalyzerInput` with an explicit start time, so result time
///    ranges are session seconds.
/// 3. Map every `SpeechTranscriber.Result` (volatile or final) through
///    `SegmentTracker`, which gives volatile and final results of one phrase
///    the same `SegmentID`.
/// 4. When the audio stream ends, finalize and finish the analyzer, so the
///    last phrase is delivered as a final result. Cancelling the consumer
///    cancels the analysis. If the analyzer's results fail mid-session, the
///    event stream ends with that error at once and the feed loop is
///    cancelled; captions do not just stop silently.
///
/// No network calls: recognition runs on device.
public struct SpeechAnalyzerTranscriber: Transcriber {
    public let locale: Locale

    public init(locale: Locale = SpeechConfiguration.locale) {
        self.locale = locale
    }

    public func transcribe(
        _ audio: AsyncThrowingStream<AudioChunk, any Error>
    ) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        let locale = self.locale
        return Self.eventStream { continuation in
            try await Self.run(locale: locale, audio: audio, continuation: continuation)
        }
    }

    typealias EventContinuation = AsyncThrowingStream<TranscriptEvent, any Error>.Continuation

    /// Runs one session in its own task and returns its events. The task is
    /// cancelled as soon as the stream terminates: when the consumer stops
    /// listening, or when the stream is finished early (see `resultsTask`).
    static func eventStream(
        _ session: @escaping @Sendable (EventContinuation) async throws -> Void
    ) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await session(continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Consumes the analyzer's results in a separate task. If that fails
    /// (and was not cancelled by the session), the event stream is finished
    /// with the error right away. That cancels the session task through
    /// `onTermination`, so the feed loop stops instead of waiting for the
    /// audio to end before the error shows.
    static func resultsTask(
        continuation: EventContinuation,
        _ consume: sending @escaping () async throws -> Void
    ) -> Task<Void, any Error> {
        Task {
            do {
                try await consume()
            } catch {
                if !Task.isCancelled {
                    continuation.finish(throwing: error)
                }
                throw error
            }
        }
    }

    // MARK: - Session

    /// Upper bound of queued analyzer inputs. The capture side never waits;
    /// if the analyzer falls this far behind, the oldest audio is dropped
    /// (inputs carry explicit times, so later results stay aligned).
    static let inputBufferLimit = 4_000

    private static func run(
        locale: Locale,
        audio: AsyncThrowingStream<AudioChunk, any Error>,
        continuation: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation
    ) async throws {
        let resolved = try await SpeechConfiguration.resolve(locale)
        let module = SpeechConfiguration.makeModule(locale: resolved)

        let status = await AssetInventory.status(forModules: [module])
        guard status == .installed else {
            throw TranscriptionError.assetsNotReady(SpeechAssetState(status))
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }

        var chunks = audio.makeAsyncIterator()
        // Wait for audio before loading the model; the first chunk also tells
        // us the origin of the stream.
        guard let first = try await chunks.next() else { return }
        try Task.checkCancellation()

        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)

        let (inputs, inputBuilder) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(inputBufferLimit)
        )
        let results = Self.resultsTask(continuation: continuation) {
            var tracker = SegmentTracker(origin: first.origin)
            for try await result in module.results {
                let phrase = RecognizedPhrase(
                    text: String(result.text.characters),
                    start: result.range.start.seconds,
                    end: result.range.end.seconds,
                    isFinal: result.isFinal
                )
                if let event = tracker.event(for: phrase) {
                    continuation.yield(event)
                }
            }
        }

        let converter = AnalyzerAudioConverter(outputFormat: format)
        let timescale = CMTimeScale(format.sampleRate.rounded())
        func feed(_ buffers: [AnalyzerAudioConverter.TimedBuffer]) {
            for timed in buffers {
                let start = CMTime(seconds: timed.startTime, preferredTimescale: timescale)
                inputBuilder.yield(AnalyzerInput(buffer: timed.buffer, bufferStartTime: start))
            }
        }

        do {
            try await analyzer.start(inputSequence: inputs)
            var next: AudioChunk? = first
            while let chunk = next {
                feed(try converter.convert(chunk))
                next = try await chunks.next()
            }
            // The audio stream also ends when this task is cancelled.
            try Task.checkCancellation()
            feed(try converter.flush())
            inputBuilder.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await results.value
        } catch {
            inputBuilder.finish()
            await analyzer.cancelAndFinishNow()
            results.cancel()
            throw error
        }
    }
}
