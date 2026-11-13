// Parts of this file are adapted from Audicap (`SCKCapture` in AudicapApp.swift),
// https://github.com/ShinoKana/audicap
// Copyright (c) 2026 ShinoKana. MIT License, see THIRD_PARTY_NOTICES.md.

import AVFoundation
import CoreMedia
import Foundation
import LiveCaptionsCore

/// Copies a ScreenCaptureKit audio sample buffer into an `AVAudioPCMBuffer`.
///
/// Uses the buffer's real stream description instead of assuming a format
/// (Audicap: a hard-coded format silently dropped every buffer when the
/// system delivered something else).
public func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard CMSampleBufferDataIsReady(sampleBuffer),
        let description = CMSampleBufferGetFormatDescription(sampleBuffer),
        let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
        let format = AVAudioFormat(streamDescription: streamDescription)
    else { return nil }
    let frames = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frames > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(frames)
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
        sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
    )
    return status == noErr ? buffer : nil
}

/// Converts PCM buffers of any format to mono Float32 at `CaptureFormat.sampleRate`
/// with `AVAudioConverter` (downmix + resample).
///
/// Not thread-safe: use it from one serial queue. It keeps one converter per
/// input format so the resampler state carries over between buffers.
public final class MonoPCMConverter {
    public let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    public init() {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: CaptureFormat.sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            preconditionFailure("16 kHz mono Float32 is always a valid format")
        }
        outputFormat = format
    }

    /// Drops the resampler state, for example before a new session.
    public func reset() {
        converter = nil
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        if buffer.format == outputFormat {
            return Self.samples(of: buffer)
        }

        let converter = try converter(for: buffer.format)
        let capacity = AVAudioFrameCount(
            CaptureFormat.convertedFrameCapacity(
                inputFrames: Int(buffer.frameLength),
                inputRate: buffer.format.sampleRate,
                outputRate: outputFormat.sampleRate
            ))
        let input = OneShotInput(buffer)
        var samples: [Float] = []
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                throw AudioCaptureError.unavailable("Could not allocate an audio buffer.")
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                input.next(inputStatus)
            }
            if status == .error {
                throw AudioCaptureError.unavailable(
                    "Audio conversion failed: \(error?.localizedDescription ?? "unknown error")"
                )
            }
            samples += Self.samples(of: output)
            // `.haveData` means the output buffer filled up and more is waiting.
            guard status == .haveData, output.frameLength > 0 else { break }
        }
        return samples
    }

    private func converter(for inputFormat: AVAudioFormat) throws -> AVAudioConverter {
        if let converter, converter.inputFormat == inputFormat {
            return converter
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.unavailable("Unsupported audio format: \(inputFormat).")
        }
        // Average all channels instead of keeping only the first one.
        converter.downmix = true
        self.converter = converter
        return converter
    }

    private static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
    }
}

/// Hands one buffer to `AVAudioConverter`, then reports "no data for now" so the
/// converter keeps its resampler state for the next buffer.
private final class OneShotInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
