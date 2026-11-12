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
