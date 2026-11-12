@preconcurrency import AVFoundation
import Foundation
import LiveCaptionsCore
import Testing
@testable import LiveCaptionsSpeech

/// Runs real English speech through `SpeechAnalyzer` + `SpeechTranscriber`.
///
/// The clip is generated at test time with macOS `say` (no audio file in the
/// repo). The test needs the en-US speech model: if it is missing it tries to
/// install it through `AssetInventory` (a system download) for up to
/// `installTimeout`. It is skipped, with the reason printed, when:
///
/// - `LIVECAPTIONS_SKIP_REAL_AUDIO=1` is set,
/// - `/usr/bin/say` is missing or cannot write a clip,
/// - `SpeechTranscriber` or en-US is unsupported on this Mac (for example on a
///   virtual machine without the speech hardware), or
/// - the model cannot be installed in time.
@Suite("SpeechAnalyzer with real audio", .serialized)
struct RealAudioTranscriptionTests {
    static let sentence = "Hello world. This is a test of live captions on the Mac."

    @Test(
        "a spoken English clip becomes stable final captions on the session time axis",
        .enabled(
            "needs `say` and the on-device en-US speech model (see the log lines starting with [real-audio])",
            { await RealAudio.prepare() }
        ),
        .timeLimit(.minutes(5))
    )
    func transcribesSpokenClip() async throws {
        let clip = try RealAudio.makeClip(saying: Self.sentence)
        defer { try? FileManager.default.removeItem(at: clip) }

        // Start at 10 s of session time to check that result ranges follow the
        // explicit buffer times, not the analyzer's own zero.
        let offset: TimeInterval = 10
        let chunks = try RealAudio.chunks(of: clip, seconds: 0.1, startingAt: offset)
        let duration = chunks.last.map(\.endTime).map { $0 - offset } ?? 0
        #expect(duration > 1)

        let audio = AsyncThrowingStream<AudioChunk, any Error> { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }

        var events: [TranscriptEvent] = []
        var store = CaptionStore()
        for try await event in SpeechAnalyzerTranscriber().transcribe(audio) {
            events.append(event)
            store.apply(event)
        }

        let volatileCount = events.filter { !$0.isFinal }.count
        let finals = events.filter(\.isFinal).map(\.segment)
        print("[real-audio] \(volatileCount) volatile and \(finals.count) final results; transcript: \(store.transcriptText)")

        // Recognised the words.
        let text = store.transcriptText.lowercased()
        #expect(text.contains("hello"))
        #expect(text.contains("test"))
        #expect(text.contains("caption"))

        // Every phrase was finalized once the input ended; no ID finalized twice.
        #expect(store.volatileSegments.isEmpty)
        #expect(Set(finals.map(\.id)).count == finals.count)

        // Volatile results reuse the ID of the phrase they belong to: every
        // volatile ID that was not abandoned ends up final.
        let finalIDs = Set(finals.map(\.id))
        let volatileIDs = Set(events.filter { !$0.isFinal }.map(\.segment.id))
        #expect(volatileIDs.isEmpty || !volatileIDs.isDisjoint(with: finalIDs))

        // Time ranges are in session seconds and inside the clip.
        for segment in store.transcript {
            #expect(segment.start >= offset - 0.5, "segment starts at \(segment.start)")
            #expect(segment.end <= offset + duration + 0.5, "segment ends at \(segment.end)")
            #expect(segment.origin == .system)
        }
    }

    @Test("a missing model is reported as an explicit state, not a crash")
    func assetStateIsExplicit() async {
        let state = await SystemSpeechAssets().currentState()
        print("[real-audio] en-US speech model state: \(state) (\(state.statusText))")
        #expect(state != .checking)
    }
}

enum RealAudio {
    static let installTimeout: Duration = .seconds(240)

    /// Checks prerequisites and installs the model if needed. Prints why the
    /// real-audio test will be skipped, if it will.
    static func prepare() async -> Bool {
        if ProcessInfo.processInfo.environment["LIVECAPTIONS_SKIP_REAL_AUDIO"] == "1" {
            return skip("LIVECAPTIONS_SKIP_REAL_AUDIO=1")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/say") else {
            return skip("/usr/bin/say is not available")
        }
        do {
            let probe = try makeClip(saying: "test")
            try? FileManager.default.removeItem(at: probe)
        } catch {
            return skip("`say` could not write a clip: \(error)")
        }

        let assets = SystemSpeechAssets()
        var state = await assets.currentState()
        log("en-US speech model state before the test: \(state.statusText)")
        switch state {
        case .ready:
            return true
        case .unsupported:
            return skip("SpeechTranscriber does not support en-US on this machine (\(state.statusText))")
        default:
            break
        }

        // Install through AssetInventory; poll so a stuck download cannot hang the run.
        log("installing the en-US speech model (timeout \(installTimeout))")
        let install = Task { await assets.install { _ in } }
        let clock = ContinuousClock()
        let deadline = clock.now + installTimeout
        while clock.now < deadline {
            try? await Task.sleep(for: .seconds(2))
            state = await assets.currentState()
            if state.isReady { break }
            if case .failed = state { break }
        }
        install.cancel()
        let installed = state.isReady
        log("en-US speech model state after install: \(state.statusText)")
        return installed ? true : skip("the en-US speech model is not installed (\(state.statusText))")
    }

    /// Writes `text` as speech to a temporary AIFF file with `say`.
    static func makeClip(saying text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "livecaptions-\(UUID().uuidString).aiff")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/say")
        process.arguments = ["-o", url.path(percentEncoded: false), text]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ClipError.sayFailed(status: process.terminationStatus)
        }
        return url
    }

    /// Reads the clip (first channel) and cuts it into mono Float32 chunks.
    static func chunks(of url: URL, seconds: TimeInterval, startingAt offset: TimeInterval) throws -> [AudioChunk] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
            format.commonFormat == .pcmFormatFloat32
        else {
            throw ClipError.unreadable
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw ClipError.unreadable }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))

        let rate = format.sampleRate
        let size = max(1, Int(rate * seconds))
        return stride(from: 0, to: samples.count, by: size).map { start in
            AudioChunk(
                samples: Array(samples[start..<min(start + size, samples.count)]),
                sampleRate: rate,
                origin: .system,
                startTime: offset + Double(start) / rate
            )
        }
    }

    enum ClipError: Error {
        case sayFailed(status: Int32)
        case unreadable
    }

    private static func skip(_ reason: String) -> Bool {
        log("SKIPPING real-audio transcription test: \(reason)")
        return false
    }

    private static func log(_ message: String) {
        print("[real-audio] \(message)")
    }
}
