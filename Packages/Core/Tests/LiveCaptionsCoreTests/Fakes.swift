import Foundation

@testable import LiveCaptionsCore

// Test doubles for the pipeline protocols. Later waves reuse these (or move
// them to a shared test-support target) instead of touching real hardware.

/// Yields a fixed list of chunks, then finishes.
final class FakeAudioSource: AudioSource {
    let origin: AudioOrigin
    private let chunks: [AudioChunk]

    init(origin: AudioOrigin = .system, chunks: [AudioChunk]) {
        self.origin = origin
        self.chunks = chunks
    }

    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func stop() async {}
}

/// Emits one volatile and one final event per chunk, with scripted text.
struct ScriptedTranscriber: Transcriber {
    let words: [String]

    func transcribe(
        _ audio: AsyncThrowingStream<AudioChunk, any Error>
    ) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        let words = self.words
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = 0
                    for try await chunk in audio {
                        let text = index < words.count ? words[index] : ""
                        let id = SegmentID()
                        let partial = TranscriptSegment(
                            id: id, text: String(text.prefix(1)),
                            start: chunk.startTime, end: chunk.endTime, origin: chunk.origin
                        )
                        continuation.yield(.volatile(partial))
                        var final = partial
                        final.text = text
                        continuation.yield(.final(final))
                        index += 1
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Records every snapshot it is asked to show.
@MainActor
final class RecordingPresenter: CaptionPresenter {
    private(set) var snapshots: [CaptionSnapshot] = []

    func present(_ snapshot: CaptionSnapshot) {
        snapshots.append(snapshot)
    }
}

/// Yields a fixed list of transcript events, then finishes. Ignores the audio.
struct ReplayTranscriber: Transcriber {
    let events: [TranscriptEvent]

    func transcribe(
        _ audio: AsyncThrowingStream<AudioChunk, any Error>
    ) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        let events = self.events
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Speech model provider with a scripted install: reports `installSteps`,
/// then ends in `installResult`.
actor ScriptedSpeechAssets: SpeechAssetProvider {
    private var state: SpeechAssetState
    private let installSteps: [SpeechAssetState]
    private let installResult: SpeechAssetState

    init(initial: SpeechAssetState, installSteps: [SpeechAssetState] = [], installResult: SpeechAssetState = .ready) {
        self.state = initial
        self.installSteps = installSteps
        self.installResult = installResult
    }

    func currentState() -> SpeechAssetState {
        state
    }

    func install(onUpdate: @escaping @Sendable (SpeechAssetState) -> Void) -> SpeechAssetState {
        guard state.canInstall else { return state }
        for step in installSteps {
            state = step
            onUpdate(step)
        }
        state = installResult
        onUpdate(installResult)
        return installResult
    }
}

/// Thread-safe list of reported values, for `@Sendable` callbacks.
final class UpdateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpeechAssetState] = []

    func append(_ value: SpeechAssetState) {
        lock.withLock { storage.append(value) }
    }

    var values: [SpeechAssetState] {
        lock.withLock { storage }
    }
}

/// Fails to start, like a source without the capture permission.
struct FailingAudioSource: AudioSource {
    let origin: AudioOrigin = .system
    let error: AudioCaptureError

    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error> {
        throw error
    }

    func stop() async {}
}

/// Yields the chunks it is given until `stop()`, like a live capture source.
final class LiveFakeAudioSource: AudioSource, @unchecked Sendable {
    let origin: AudioOrigin = .system
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?
    private var stopCount = 0

    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error> {
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream()
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func yield(_ chunk: AudioChunk) {
        _ = lock.withLock { continuation }?.yield(chunk)
    }

    func fail(_ error: any Error) {
        lock.withLock { continuation }?.finish(throwing: error)
    }

    func stop() async {
        let continuation = lock.withLock { () -> AsyncThrowingStream<AudioChunk, any Error>.Continuation? in
            stopCount += 1
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish()
    }

    var stops: Int { lock.withLock { stopCount } }

    var isStarted: Bool { lock.withLock { continuation != nil } }
}

/// Throws `error` as soon as audio arrives, like a transcriber without its model.
struct FailingTranscriber: Transcriber {
    let error: TranscriptionError

    func transcribe(
        _ audio: AsyncThrowingStream<AudioChunk, any Error>
    ) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        let error = self.error
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await _ in audio {
                        continuation.finish(throwing: error)
                        return
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Yields the transcript events the test sends while the audio runs, and
/// finishes when the audio ends. Ignores the audio itself.
final class ControlledTranscriber: Transcriber, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?

    func transcribe(
        _ audio: AsyncThrowingStream<AudioChunk, any Error>
    ) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        let (events, continuation) = AsyncThrowingStream<TranscriptEvent, any Error>.makeStream()
        lock.withLock { self.continuation = continuation }
        let task = Task {
            do {
                for try await _ in audio {}
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return events
    }

    func send(_ event: TranscriptEvent) {
        _ = lock.withLock { continuation }?.yield(event)
    }

    var isTranscribing: Bool { lock.withLock { continuation != nil } }
}

/// A sleep the test ends by hand: `sleep(_:)` records the delay and waits
/// until `wakeAll()` (or cancellation).
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var delays: [TimeInterval] = []

    /// Every delay asked for so far.
    var requestedDelays: [TimeInterval] { lock.withLock { delays } }

    /// How many sleeps are waiting right now.
    var sleeping: Int { lock.withLock { waiting.count } }

    func sleep(_ seconds: TimeInterval) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let cancelled = lock.withLock { () -> Bool in
                    delays.append(seconds)
                    if Task.isCancelled { return true }
                    waiting[id] = continuation
                    return false
                }
                if cancelled { continuation.resume() }
            }
        } onCancel: {
            lock.withLock { waiting.removeValue(forKey: id) }?.resume()
        }
    }

    func wakeAll() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { waiting.removeAll() }
            return Array(waiting.values)
        }
        for continuation in all {
            continuation.resume()
        }
    }
}

/// Session time the test sets by hand.
@MainActor
final class ManualClock {
    var now: TimeInterval = 0
}
