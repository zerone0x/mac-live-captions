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

/// Whether `count` output frames are one second at 16 kHz, less the frames
/// the resampler holds back. AVAudioConverter keeps a constant latency
/// (about 16 ms from 48 kHz on macOS 26) because the converter is never
/// flushed between buffers; allow up to 30 ms.
private func isAboutOneSecond(_ count: Int) -> Bool {
    (16_000 - 480)...(16_000 + 16) ~= count
}

/// Feeds one second (second number `second` of a continuous signal) as ten
/// 100 ms buffers and returns all output samples.
private func convertOneSecond(
    _ converter: MonoPCMConverter,
    rate: Double,
    channels: Int,
    second: Int = 0,
    _ channel: @escaping (Int, Int) -> Float
) throws -> [Float] {
    let frames = Int(rate / 10)
    var output: [Float] = []
    for index in 0..<10 {
        let buffer = try floatBuffer(
            sampleRate: rate, channels: channels, frames: frames,
            firstFrame: (second * 10 + index) * frames, channel
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

    @Test("stereo in 100 ms buffers is resampled to 16 kHz without losing frames between buffers", arguments: [48_000.0, 44_100.0])
    func resamplesAcrossBuffers(rate: Double) throws {
        let converter = MonoPCMConverter()
        let samples = try convertOneSecond(converter, rate: rate, channels: 2) { _, frame in
            sine(frame, rate: rate)
        }
        var total = samples.count
        var perSecond = [samples.count]
        for second in 1..<10 {
            let next = try convertOneSecond(converter, rate: rate, channels: 2, second: second) { _, frame in
                sine(frame, rate: rate)
            }
            total += next.count
            perSecond.append(next.count)
        }
        #expect(isAboutOneSecond(samples.count), "got \(samples.count) samples for the first second")
        // The resampler's latency stays bounded: after 100 buffers the output
        // is still short by no more than 30 ms. Losing even a few frames per
        // buffer (a converter rebuilt or drained wrongly per call) adds up
        // past that.
        let shortfall = 10 * 16_000 - total
        #expect((-16...480).contains(shortfall), "short by \(shortfall) frames after 10 s; per second: \(perSecond)")
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
        #expect(isAboutOneSecond(samples.count), "got \(samples.count) samples")
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
            #expect(isAboutOneSecond(samples.count), "got \(samples.count) samples")
        }
    }
}
