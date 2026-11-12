@preconcurrency import AVFoundation
import Foundation
import LiveCaptionsCore

/// Converts Core `AudioChunk`s (mono Float32 at any rate) into buffers in the
/// analyzer's format, each with a session start time.
///
/// `SpeechAnalyzer` "does not transparently upsample, downsample, or convert
/// audio input" (Apple docs), and `AnalyzerInputConverter` needs macOS 27, so
/// this uses `AVAudioConverter`. Times come from `AudioTimeline` (Core).
///
/// Not thread-safe; one instance per transcription run.
final class AnalyzerAudioConverter {
    struct TimedBuffer {
        let buffer: AVAudioPCMBuffer
        /// Session seconds of the first frame.
        let startTime: TimeInterval
    }

    let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var timeline = AudioTimeline()

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    /// Converts one chunk. May return no buffer while the resampler fills up.
    func convert(_ chunk: AudioChunk) throws -> [TimedBuffer] {
        guard !chunk.samples.isEmpty else { return [] }
        let input = try Self.makeBuffer(chunk)

        if timeline.accept(chunkStart: chunk.startTime, duration: chunk.duration) {
            // New contiguous run: drop resampler state from the previous run.
            converter?.reset()
        }

        let output: AVAudioPCMBuffer
        if input.format == outputFormat {
            output = input
        } else {
            output = try resample(input, endOfStream: false)
        }
        return place(output)
    }

    /// Drains frames the resampler still holds. Call once at the end of input.
    func flush() throws -> [TimedBuffer] {
        guard converter != nil else { return [] }
        return place(try resample(nil, endOfStream: true))
    }

    // MARK: - Private

    private func place(_ buffer: AVAudioPCMBuffer) -> [TimedBuffer] {
        guard buffer.frameLength > 0 else { return [] }
        let start = timeline.place(frames: Int(buffer.frameLength), sampleRate: outputFormat.sampleRate)
        return [TimedBuffer(buffer: buffer, startTime: start)]
    }

    private func resample(_ input: AVAudioPCMBuffer?, endOfStream: Bool) throws -> AVAudioPCMBuffer {
        let active = try makeConverter(for: input?.format)
        let inputRate = active.inputFormat.sampleRate
        let inputFrames = Double(input?.frameLength ?? 0)
        let capacity = AVAudioFrameCount((inputFrames * outputFormat.sampleRate / inputRate).rounded(.up)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw TranscriptionError.audioConversionFailed("could not allocate an output buffer")
        }

        let feed = InputFeed(input, endOfStream: endOfStream)
        var error: NSError?
        let status = active.convert(to: output, error: &error) { _, inputStatus in
            feed.next(inputStatus)
        }
        if status == .error {
            throw TranscriptionError.audioConversionFailed(error?.localizedDescription ?? "AVAudioConverter error")
        }
        if endOfStream {
            // A converter that reached end of stream must be reset before reuse.
            active.reset()
        }
        return output
    }

    private func makeConverter(for inputFormat: AVAudioFormat?) throws -> AVAudioConverter {
        if let converter, inputFormat == nil || converter.inputFormat == inputFormat {
            return converter
        }
        guard let inputFormat, let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw TranscriptionError.audioConversionFailed("unsupported conversion to \(outputFormat)")
        }
        self.converter = converter
        return converter
    }

    static func makeBuffer(_ chunk: AudioChunk) throws -> AVAudioPCMBuffer {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: chunk.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.samples.count)),
            let channel = buffer.floatChannelData?[0]
        else {
            throw TranscriptionError.audioConversionFailed("could not build a \(chunk.sampleRate) Hz buffer")
        }
        chunk.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        return buffer
    }
}

/// Hands the converter one input buffer, then reports "no data now" (or end
/// of stream when flushing). A class so the converter's input block can
/// capture it without capturing mutable local state.
private final class InputFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    private let endOfStream: Bool

    init(_ buffer: AVAudioPCMBuffer?, endOfStream: Bool) {
        self.buffer = buffer
        self.endOfStream = endOfStream
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if let buffer {
            self.buffer = nil
            status.pointee = .haveData
            return buffer
        }
        status.pointee = endOfStream ? .endOfStream : .noDataNow
        return nil
    }
}
