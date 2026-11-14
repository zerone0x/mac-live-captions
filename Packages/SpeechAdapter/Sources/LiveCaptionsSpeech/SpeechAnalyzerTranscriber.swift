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
///    cancels the analysis.
/// 5. Input start times are whole frames at the analyzer's sample rate and
///    strictly ordered (`InputFeeder`, issue #48). If the analyzer still
///    fails mid-session, a new analyzer is started on the same audio and
///    time axis, at most `AnalyzerRestartBudget` times in a window; after
///    that the event stream ends with `TranscriptionError.analyzerStopped`,
///    so captions do not just stop silently (DECISIONS 0024).
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
        resultsTask(onFailure: { continuation.finish(throwing: $0) }, consume)
    }

    /// Like `resultsTask(continuation:_:)`, but hands a failure that was not
    /// caused by cancellation to `onFailure`. The session uses this to
    /// restart the analyzer (DECISIONS 0024).
    static func resultsTask(
        onFailure: @escaping @Sendable (any Error) -> Void,
        _ consume: sending @escaping () async throws -> Void
    ) -> Task<Void, any Error> {
        Task {
            do {
                try await consume()
            } catch {
                if !Task.isCancelled {
                    onFailure(error)
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
        let probe = SpeechConfiguration.makeModule(locale: resolved)

        let status = await AssetInventory.status(forModules: [probe])
        guard status == .installed else {
            throw TranscriptionError.assetsNotReady(SpeechAssetState(status))
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }

        var chunks = audio.makeAsyncIterator()
        // Wait for audio before loading the model; the first chunk also tells
        // us the origin of the stream.
        guard let first = try await chunks.next() else { return }
        try Task.checkCancellation()

        // One converter and one input guard for the whole session, across
        // analyzer restarts: input times stay on one monotonic frame axis.
        let feeder = InputFeeder(converter: AnalyzerAudioConverter(outputFormat: format))
        var restarts = AnalyzerRestartBudget()
        var next: AudioChunk? = first
        while true {
            let module = SpeechConfiguration.makeModule(locale: resolved)
            let outcome = try await analyze(
                module: module,
                format: format,
                origin: first.origin,
                next: &next,
                chunks: &chunks,
                feeder: feeder,
                continuation: continuation
            )
            guard case .failed(let error) = outcome else { return }
            // Restart with the chunk that was waiting when the failure showed
            // (DECISIONS 0024). The budget keeps a failure that repeats at once
            // from looping.
            guard let pending = next else { return }
            guard restarts.requestRestart(at: pending.startTime) else {
                throw TranscriptionError.analyzerStopped(
                    restarts: restarts.recentRestarts,
                    reason: (error as NSError).localizedDescription
                )
            }
        }
    }

    enum AnalyzerOutcome {
        /// The audio ended and the last results were delivered.
        case finished
        /// The analyzer failed; `next` holds the chunk to resume with.
        case failed(any Error)
    }

    /// Runs one `SpeechAnalyzer` until the audio ends or the analyzer fails.
    /// Errors from the audio source and cancellation are thrown; analyzer
    /// errors are returned so the caller can restart.
    private static func analyze(
        module: SpeechTranscriber,
        format: AVAudioFormat,
        origin: AudioOrigin,
        next: inout AudioChunk?,
        chunks: inout AsyncThrowingStream<AudioChunk, any Error>.AsyncIterator,
        feeder: InputFeeder,
        continuation: EventContinuation
    ) async throws -> AnalyzerOutcome {
        let analyzer = SpeechAnalyzer(modules: [module])
        let failure = FailureBox()
        let (inputs, inputBuilder) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(inputBufferLimit)
        )
        // A results failure is recorded, not thrown into the event stream:
        // the feed loop sees it at the next chunk and restarts the analyzer.
        let recordFailure: @Sendable (any Error) -> Void = { failure.record($0) }
        let results = Self.resultsTask(onFailure: recordFailure) {
            var tracker = SegmentTracker(origin: origin)
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
        func tearDown() async {
            inputBuilder.finish()
            await analyzer.cancelAndFinishNow()
            results.cancel()
        }

        do {
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: inputs)
        } catch {
            await tearDown()
            try Task.checkCancellation()
            return .failed(error)
        }

        do {
            while let chunk = next {
                if let error = failure.error {
                    await tearDown()
                    return .failed(error)
                }
                feeder.feed(try feeder.convert(chunk), into: inputBuilder)
                next = try await chunks.next()
            }
            // The audio stream also ends when this task is cancelled.
            try Task.checkCancellation()
            feeder.feed(try feeder.flush(), into: inputBuilder)
        } catch {
            // Audio source, conversion or cancellation: not restartable.
            await tearDown()
            throw error
        }

        inputBuilder.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await results.value
        } catch {
            await tearDown()
            try Task.checkCancellation()
            // The audio has ended: nothing is left to restart for.
            throw failure.error ?? error
        }
        if let error = failure.error {
            throw error
        }
        return .finished
    }
}

/// Converts chunks and hands them to the analyzer with sample-exact,
/// strictly ordered start times (issue #48, DECISIONS 0024).
///
/// Every start goes through `MonotonicInputGuard` with the buffer's real
/// `frameLength` and becomes `CMTime(value: frame, timescale: sampleRate)`,
/// so no input can start before the previous one ends.
final class InputFeeder {
    private let converter: AnalyzerAudioConverter
    private var gate = MonotonicInputGuard()

    init(converter: AnalyzerAudioConverter) {
        self.converter = converter
    }

    /// Inputs the guard moved later (0 unless the timeline is wrong).
    var shiftedInputs: Int { gate.shiftedInputs }

    func convert(_ chunk: AudioChunk) throws -> [AnalyzerAudioConverter.TimedBuffer] {
        try converter.convert(chunk)
    }

    func flush() throws -> [AnalyzerAudioConverter.TimedBuffer] {
        try converter.flush()
    }

    /// The buffers to feed with their checked start times. Empty buffers are
    /// left out.
    func admit(
        _ buffers: [AnalyzerAudioConverter.TimedBuffer]
    ) -> [(buffer: AVAudioPCMBuffer, start: CMTime)] {
        buffers.compactMap { timed in
            let frames = Int(timed.buffer.frameLength)
            guard let frame = gate.admit(start: timed.startFrame, frames: frames) else { return nil }
            return (timed.buffer, CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(timed.sampleRate)))
        }
    }

    func feed(
        _ buffers: [AnalyzerAudioConverter.TimedBuffer],
        into builder: AsyncStream<AnalyzerInput>.Continuation
    ) {
        for input in admit(buffers) {
            builder.yield(AnalyzerInput(buffer: input.buffer, bufferStartTime: input.start))
        }
    }
}

/// The first error of an analyzer's results task, read by the feed loop.
final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (any Error)?

    var error: (any Error)? { lock.withLock { stored } }

    func record(_ error: any Error) {
        lock.withLock {
            if stored == nil { stored = error }
        }
    }
}
