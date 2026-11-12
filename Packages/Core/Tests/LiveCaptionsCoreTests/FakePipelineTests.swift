import Foundation
import Testing
@testable import LiveCaptionsCore

/// Shows the testing convention: wire fakes through the pipeline protocols and
/// assert on what the presenter receives. No audio hardware, no permissions.
@Suite("Fake pipeline")
struct FakePipelineTests {
    @Test("fakes compose: audio -> transcript events -> presenter")
    @MainActor
    func fakesCompose() async throws {
        let chunks = (0..<3).map { index in
            AudioChunk(
                samples: Array(repeating: 0, count: 1_600),
                sampleRate: 16_000,
                origin: .system,
                startTime: Double(index) * 0.1
            )
        }
        let source = FakeAudioSource(chunks: chunks)
        let transcriber = ScriptedTranscriber(words: ["hello", "live", "captions"])
        let presenter = RecordingPresenter()

        let audio = try await source.start()
        var events: [TranscriptEvent] = []
        for try await event in transcriber.transcribe(audio) {
            events.append(event)
            // Stand-in for the CaptionStore (#8): show the latest segment only.
            let segment = event.segment
            presenter.present(CaptionSnapshot(lines: [
                CaptionLine(id: segment.id, text: segment.text, origin: segment.origin, isFinal: event.isFinal),
            ]))
        }

        #expect(events.count == 6)
        #expect(events.filter(\.isFinal).map(\.segment.text) == ["hello", "live", "captions"])
        #expect(presenter.snapshots.last?.lines.map(\.text) == ["captions"])
        #expect(presenter.snapshots.last?.lines.first?.isFinal == true)

        let finals = events.filter(\.isFinal).map(\.segment)
        #expect(finals.map(\.start) == [0, 0.1, 0.2])
        #expect(finals.allSatisfy { $0.end > $0.start })
    }
}
