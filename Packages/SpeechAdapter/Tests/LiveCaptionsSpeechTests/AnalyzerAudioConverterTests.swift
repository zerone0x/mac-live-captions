@preconcurrency import AVFoundation
import Foundation
import LiveCaptionsCore
import Speech
import Testing

@testable import LiveCaptionsSpeech

private func sineChunks(count: Int, sampleRate: Double, seconds: Double, firstStart: TimeInterval) -> [AudioChunk] {
    let frames = Int(sampleRate * seconds)
    return (0..<count).map { index in
        let samples = (0..<frames).map { frame in
            Float(sin(2 * Double.pi * 440 * Double(index * frames + frame) / sampleRate) * 0.5)
        }
        return AudioChunk(
            samples: samples,
            sampleRate: sampleRate,
            origin: .system,
            startTime: firstStart + Double(index) * seconds
        )
    }
}

private func int16Mono16k() -> AVAudioFormat {
    AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
}

@Suite("AnalyzerAudioConverter")
struct AnalyzerAudioConverterTests {
    @Test("48 kHz Float32 chunks are resampled to 16 kHz Int16 on the session time axis")
    func resamples() throws {
        let converter = AnalyzerAudioConverter(outputFormat: int16Mono16k())
        var buffers: [AnalyzerAudioConverter.TimedBuffer] = []
        for chunk in sineChunks(count: 10, sampleRate: 48_000, seconds: 0.1, firstStart: 2) {
            buffers += try converter.convert(chunk)
        }
        buffers += try converter.flush()

        #expect(!buffers.isEmpty)
        #expect(buffers.allSatisfy { $0.buffer.format == int16Mono16k() })
        let totalFrames = buffers.reduce(0) { $0 + Int($1.buffer.frameLength) }
        // The resampler may keep a few milliseconds of latency it never emits.
        #expect(abs(totalFrames - 16_000) <= 160, "got \(totalFrames) frames for 1 s of audio")

        #expect(buffers.first?.startTime == 2)
        for (previous, next) in zip(buffers, buffers.dropFirst()) {
            let expected = previous.startTime + Double(previous.buffer.frameLength) / 16_000
            #expect(abs(next.startTime - expected) < 1e-9)
        }
    }

    @Test("a gap in the input re-anchors the output time")
    func gapReanchors() throws {
        let converter = AnalyzerAudioConverter(outputFormat: int16Mono16k())
        for chunk in sineChunks(count: 3, sampleRate: 48_000, seconds: 0.1, firstStart: 0) {
            _ = try converter.convert(chunk)
        }
        let later = sineChunks(count: 1, sampleRate: 48_000, seconds: 0.1, firstStart: 10)[0]
        let buffers = try converter.convert(later)
        #expect(buffers.first?.startTime == 10)
    }

    @Test("audio already in the analyzer format passes through unchanged")
    func passthrough() throws {
        let float16k = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = AnalyzerAudioConverter(outputFormat: float16k)
        let chunks = sineChunks(count: 2, sampleRate: 16_000, seconds: 0.05, firstStart: 1)
        let first = try converter.convert(chunks[0])
        let second = try converter.convert(chunks[1])

        #expect(first.map(\.startTime) == [1])
        #expect(second.map(\.startTime) == [1.05])
        #expect(first.first?.buffer.frameLength == 800)
        let samples = try #require(second.first?.buffer.floatChannelData?[0])
        #expect(samples[10] == chunks[1].samples[10])
        #expect(try converter.flush().isEmpty)
    }

    @Test("an empty chunk produces nothing")
    func emptyChunk() throws {
        let converter = AnalyzerAudioConverter(outputFormat: int16Mono16k())
        let empty = AudioChunk(samples: [], sampleRate: 48_000, origin: .system, startTime: 0)
        #expect(try converter.convert(empty).isEmpty)
    }

    @Test("a changed input sample rate gets a new converter")
    func sampleRateChange() throws {
        let converter = AnalyzerAudioConverter(outputFormat: int16Mono16k())
        _ = try converter.convert(sineChunks(count: 1, sampleRate: 48_000, seconds: 0.1, firstStart: 0)[0])
        let buffers = try converter.convert(sineChunks(count: 1, sampleRate: 44_100, seconds: 0.1, firstStart: 0.1)[0])
        let frames = buffers.reduce(0) { $0 + Int($1.buffer.frameLength) }
        #expect(frames > 0 && frames <= 1_700)
    }
}

@Suite("Speech asset status mapping")
struct SpeechAssetMappingTests {
    @Test("AssetInventory statuses map to explicit states")
    func mapping() {
        #expect(SpeechAssetState(AssetInventory.Status.installed) == .ready)
        #expect(SpeechAssetState(AssetInventory.Status.downloading) == .downloading(fractionCompleted: nil))
        #expect(SpeechAssetState(AssetInventory.Status.supported) == .notInstalled)
        #expect(SpeechAssetState(AssetInventory.Status.unsupported) == .unsupported)
    }

    @Test("the recogniser is configured for en-US")
    func locale() {
        #expect(SpeechConfiguration.localeIdentifier == "en-US")
        #expect(SpeechAnalyzerTranscriber().locale.identifier(.bcp47) == "en-US")
        #expect(SystemSpeechAssets().locale.identifier(.bcp47) == "en-US")
    }
}
