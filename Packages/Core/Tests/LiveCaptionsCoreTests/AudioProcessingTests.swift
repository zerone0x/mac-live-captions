import Foundation
import Testing
@testable import LiveCaptionsCore

@Suite("Audio processing")
struct AudioProcessingTests {
    // MARK: Conversion math

    @Test("converted capacity rounds up and adds headroom", arguments: [
        // 48 kHz -> 16 kHz: 1024 frames -> 341.33 -> 342
        (1_024, 48_000.0, 16_000.0, 342 + 64),
        // 44.1 kHz -> 16 kHz: 441 frames -> exactly 160
        (441, 44_100.0, 16_000.0, 160 + 64),
        // same rate keeps the frame count
        (1_600, 16_000.0, 16_000.0, 1_600 + 64),
        // upsampling 8 kHz -> 16 kHz doubles
        (100, 8_000.0, 16_000.0, 200 + 64),
        (0, 48_000.0, 16_000.0, 64),
    ])
    func convertedCapacity(frames: Int, inputRate: Double, outputRate: Double, expected: Int) {
        #expect(CaptureFormat.convertedFrameCapacity(
            inputFrames: frames, inputRate: inputRate, outputRate: outputRate
        ) == expected)
    }

    @Test("capacity is never smaller than the converted frame count")
    func capacityCoversOutput() {
        for frames in [1, 7, 480, 512, 1_023, 4_096] {
            for rate in [22_050.0, 44_100.0, 48_000.0, 96_000.0] {
                let capacity: Int = CaptureFormat.convertedFrameCapacity(
                    inputFrames: frames, inputRate: rate, outputRate: CaptureFormat.sampleRate, headroom: 0
                )
                let needed: Double = Double(frames) * CaptureFormat.sampleRate / rate
                #expect(Double(capacity) >= needed)
            }
        }
    }

    // MARK: Level

    @Test("level of a full-scale square wave is 0 dBFS")
    func fullScale() {
        let level = AudioLevel(samples: [1, -1, 1, -1])
        #expect(level.peak == 1)
        #expect(level.rms == 1)
        #expect(level.decibels == 0)
        #expect(level.meterFraction == 1)
    }

    @Test("silence is -100 dB and an empty meter")
    func silence() {
        let level = AudioLevel(samples: [Float](repeating: 0, count: 160))
        #expect(level == .silence)
        #expect(level.decibels == -100)
        #expect(level.meterFraction == 0)
        #expect(AudioLevel(samples: []) == .silence)
    }

    @Test("half-scale square wave is about -6 dB, a tenth of the meter range")
    func halfScale() {
        let level = AudioLevel(samples: [0.5, -0.5, 0.5, -0.5])
        #expect(level.peak == 0.5)
        let expectedDecibels: Float = -6.0206
        let decibelError: Float = abs(level.decibels - expectedDecibels)
        #expect(decibelError < 0.001)
        let expectedFraction: Double = 1 - 6.0206 / 60
        let fractionError: Double = abs(level.meterFraction - expectedFraction)
        #expect(fractionError < 0.001)
    }

    // MARK: Chunking

    @Test("assembler emits 100 ms chunks with session times from the frame count")
    func chunking() {
        var assembler = AudioChunkAssembler(origin: .system)
        #expect(assembler.framesPerChunk == 1_600)

        // 1000 frames: not enough for a chunk yet.
        #expect(assembler.append([Float](repeating: 0.1, count: 1_000)).isEmpty)
        // +2500 = 3500 frames: two chunks, 300 pending.
        let chunks = assembler.append([Float](repeating: 0.2, count: 2_500))
        #expect(chunks.count == 2)
        let startTimes: [TimeInterval] = chunks.map(\.startTime)
        #expect(startTimes == [0, 0.1])
        for chunk in chunks {
            #expect(chunk.samples.count == 1_600)
            #expect(chunk.origin == .system)
            #expect(chunk.sampleRate == 16_000)
        }
        // Sample order is kept across appends.
        let first: [Float] = chunks[0].samples
        #expect(first[0..<1_000].allSatisfy { $0 == 0.1 })
        #expect(first[1_000...].allSatisfy { $0 == 0.2 })
        let durationError: Double = abs(assembler.capturedDuration - 3_500.0 / 16_000)
        #expect(durationError < 1e-9)

        let tail = assembler.flush()
        #expect(tail?.samples.count == 300)
        #expect(tail?.startTime == 0.2)
        #expect(assembler.flush() == nil)
    }

    @Test("chunks are contiguous: each starts where the previous ended")
    func contiguous() {
        var assembler = AudioChunkAssembler(origin: .microphone, sampleRate: 16_000, chunkDuration: 0.05)
        let sizes: [Int] = [17, 4_000, 1, 799, 2_048, 333]
        var chunks: [AudioChunk] = []
        for size in sizes {
            chunks += assembler.append([Float](repeating: 0, count: size))
        }
        if let tail = assembler.flush() { chunks.append(tail) }
        let emitted: Int = chunks.map(\.samples.count).reduce(0, +)
        let appended: Int = sizes.reduce(0, +)
        #expect(emitted == appended)
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            let gap: Double = abs(previous.endTime - next.startTime)
            #expect(gap < 1e-9)
        }
    }

    @Test("reset starts a new session at time zero")
    func reset() {
        var assembler = AudioChunkAssembler(origin: .system)
        _ = assembler.append([Float](repeating: 0, count: 5_000))
        assembler.reset()
        #expect(assembler.capturedDuration == 0)
        let next = assembler.append([Float](repeating: 0, count: 1_600))
        #expect(next.first?.startTime == 0)
    }

    // MARK: Silence

    @Test("silence is reported once after the timeout, sound once when it returns")
    func silenceMonitor() {
        var monitor = SilenceMonitor(timeout: 1)
        let quiet = AudioLevel.silence
        let loud = AudioLevel(peak: 0.3, rms: 0.1)

        #expect(monitor.process(loud, duration: 0.1) == nil)
        var events: [AudioCaptureEvent?] = []
        for _ in 0..<12 {
            events.append(monitor.process(quiet, duration: 0.1))
        }
        let reported: [AudioCaptureEvent] = events.compactMap { $0 }
        #expect(reported == [.silenceDetected])
        let index: Int? = events.firstIndex(of: .silenceDetected)
        #expect(index == 9) // 10 x 0.1 s = 1 s
        #expect(monitor.isSilent)
        #expect(monitor.process(loud, duration: 0.1) == .soundDetected)
        #expect(monitor.process(loud, duration: 0.1) == nil)
        #expect(!monitor.isSilent)
    }

    @Test("a short pause does not count as no audio")
    func shortPause() {
        var monitor = SilenceMonitor(timeout: 5)
        for _ in 0..<40 { #expect(monitor.process(.silence, duration: 0.1) == nil) }
        #expect(monitor.process(AudioLevel(peak: 0.2, rms: 0.1), duration: 0.1) == nil)
        for _ in 0..<40 { #expect(monitor.process(.silence, duration: 0.1) == nil) }
    }

    @Test("near-silent dither below the threshold still counts as silence")
    func ditherIsSilence() {
        var monitor = SilenceMonitor(threshold: 1e-4, timeout: 0.2)
        let dither = AudioLevel(samples: [0.00005, -0.00003, 0.00008])
        #expect(monitor.process(dither, duration: 0.1) == nil)
        #expect(monitor.process(dither, duration: 0.1) == .silenceDetected)
    }

    // MARK: Retry

    @Test("retry backs off exponentially, capped, then gives up")
    func retryPolicy() {
        let policy = CaptureRetryPolicy()
        let delays: [TimeInterval?] = (1...6).map { policy.delay(forAttempt: $0) }
        #expect(delays == [2, 4, 8, 16, 30, 30])
        #expect(policy.delay(forAttempt: 7) == nil)
        #expect(policy.delay(forAttempt: 0) == nil)
        #expect(CaptureRetryPolicy(maxAttempts: 0).delay(forAttempt: 1) == nil)
    }
}
