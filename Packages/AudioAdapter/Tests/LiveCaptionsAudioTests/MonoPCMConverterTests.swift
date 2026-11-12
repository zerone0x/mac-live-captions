import AVFoundation
import Foundation
import LiveCaptionsCore
import Testing
@testable import LiveCaptionsAudio

/// A non-interleaved Float32 buffer; `channel(c, frame)` gives each sample.
private func floatBuffer(
    sampleRate: Double,
    channels: Int,
    frames: Int,
    firstFrame: Int = 0,
    _ channel: (Int, Int) -> Float
) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: AVAudioChannelCount(channels),
        interleaved: false
    ))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
    buffer.frameLength = AVAudioFrameCount(frames)
    let data = try #require(buffer.floatChannelData)
    for c in 0..<channels {
        for frame in 0..<frames {
            data[c][frame] = channel(c, firstFrame + frame)
        }
    }
    return buffer
}

/// An interleaved Int16 buffer with the same sample on every channel.
private func int16InterleavedBuffer(
    sampleRate: Double,
    channels: Int,
    frames: Int,
    firstFrame: Int,
    _ sample: (Int) -> Int16
) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: AVAudioChannelCount(channels),
        interleaved: true
    ))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
    buffer.frameLength = AVAudioFrameCount(frames)
    let data = try #require(buffer.int16ChannelData)
    for frame in 0..<frames {
        for c in 0..<channels {
            data[0][frame * channels + c] = sample(firstFrame + frame)
        }
    }
    return buffer
}

private func sine(_ frame: Int, rate: Double, amplitude: Float = 0.5, hz: Double = 440) -> Float {
    Float(sin(2 * Double.pi * hz * Double(frame) / rate)) * amplitude
}

private func peak(_ samples: [Float]) -> Float {
    samples.reduce(0) { max($0, abs($1)) }
}

/// Feeds one second as ten 100 ms buffers and returns all output samples.
private func convertOneSecond(
    _ converter: MonoPCMConverter,
    rate: Double,
    channels: Int,
    _ channel: @escaping (Int, Int) -> Float
) throws -> [Float] {
    let frames = Int(rate / 10)
    var output: [Float] = []
    for index in 0..<10 {
        let buffer = try floatBuffer(
            sampleRate: rate, channels: channels, frames: frames, firstFrame: index * frames, channel
        )
        output += try converter.convert(buffer)
    }
    return output
}

@Suite("MonoPCMConverter")
struct MonoPCMConverterTests {
    @Test("output format is 16 kHz mono Float32")
    func outputFormat() {
        let format = MonoPCMConverter().outputFormat
        #expect(format.sampleRate == CaptureFormat.sampleRate)
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatFloat32)
    }

    @Test("16 kHz mono Float32 passes through sample for sample")
    func passthrough() throws {
        let converter = MonoPCMConverter()
        let buffer = try floatBuffer(sampleRate: 16_000, channels: 1, frames: 1_600) { _, frame in
            sine(frame, rate: 16_000)
        }
        let samples = try converter.convert(buffer)
        #expect(samples.count == 1_600)
        #expect(samples[123] == sine(123, rate: 16_000))
    }

    @Test("an empty buffer gives no samples")
    func emptyBuffer() throws {
        let converter = MonoPCMConverter()
        let buffer = try floatBuffer(sampleRate: 48_000, channels: 2, frames: 0) { _, _ in 0 }
        #expect(try converter.convert(buffer).isEmpty)
    }

    @Test("48 kHz stereo in 100 ms buffers becomes about one second at 16 kHz", arguments: [48_000.0, 44_100.0])
    func resamplesAcrossBuffers(rate: Double) throws {
        let converter = MonoPCMConverter()
        let samples = try convertOneSecond(converter, rate: rate, channels: 2) { _, frame in
            sine(frame, rate: rate)
        }
        // The resampler keeps a few milliseconds of latency between calls.
        #expect(abs(samples.count - 16_000) <= 160, "got \(samples.count) samples for 1 s")
        #expect(peak(samples) > 0.3)
        #expect(peak(samples) <= 1.01, "mixing identical channels must not clip")
    }

    @Test("both channels are mixed: opposite-phase stereo cancels out")
    func downmixAveragesChannels() throws {
        let converter = MonoPCMConverter()
        let samples = try convertOneSecond(converter, rate: 48_000, channels: 2) { channel, frame in
            channel == 0 ? sine(frame, rate: 48_000) : -sine(frame, rate: 48_000)
        }
        #expect(!samples.isEmpty)
        #expect(peak(samples) < 0.01, "keeping only the left channel would give 0.5")
    }

    @Test("audio on the right channel only is not dropped")
    func rightChannelIsKept() throws {
        let converter = MonoPCMConverter()
        let samples = try convertOneSecond(converter, rate: 48_000, channels: 2) { channel, frame in
            channel == 1 ? sine(frame, rate: 48_000) : 0
        }
        #expect(peak(samples) > 0.1)
    }

    @Test("interleaved Int16 input is converted to Float32 in -1...1")
    func int16Input() throws {
        let converter = MonoPCMConverter()
        var samples: [Float] = []
        for index in 0..<10 {
            let buffer = try int16InterleavedBuffer(
                sampleRate: 48_000, channels: 2, frames: 4_800, firstFrame: index * 4_800
            ) { frame in
                Int16(sine(frame, rate: 48_000) * Float(Int16.max))
            }
            samples += try converter.convert(buffer)
        }
        #expect(abs(samples.count - 16_000) <= 160)
        #expect(peak(samples) > 0.3)
        #expect(peak(samples) <= 1.01)
    }

    @Test("a format change mid-stream and reset both keep converting")
    func formatChangeAndReset() throws {
        let converter = MonoPCMConverter()
        let first = try convertOneSecond(converter, rate: 48_000, channels: 2) { _, frame in sine(frame, rate: 48_000) }
        let second = try convertOneSecond(converter, rate: 44_100, channels: 1) { _, frame in sine(frame, rate: 44_100) }
        converter.reset()
        let third = try convertOneSecond(converter, rate: 48_000, channels: 2) { _, frame in sine(frame, rate: 48_000) }
        for samples in [first, second, third] {
            #expect(abs(samples.count - 16_000) <= 160)
        }
    }
}
