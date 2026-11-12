// Adapted from Audicap (`MicCapture` and `builtInInputDeviceID()` in AudicapApp.swift),
// https://github.com/ShinoKana/audicap
// Copyright (c) 2026 ShinoKana. MIT License, see THIRD_PARTY_NOTICES.md.

import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import LiveCaptionsAudio
import LiveCaptionsCore

/// Captures the built-in microphone with `AVAudioEngine`. Off by default: the
/// user turns it on explicitly to caption their own voice.
///
/// Binds the built-in microphone instead of following the default input: when
/// Bluetooth headphones are the default input, opening their microphone drops
/// them from A2DP to the HFP call profile and playback quality falls apart.
/// Rebuilds the engine when the audio configuration changes (headphones
/// plugged in or out).
///
/// Uses the same run tokens as `SystemAudioSource` (DECISIONS 0012): a
/// `stop()` while the permission prompt is open, or a configuration change
/// racing `stop()`, can never leave an engine running. `onStatus` is called
/// one at a time, in order, and must not call back into the source.
final class MicrophoneAudioSource: AudioSource, @unchecked Sendable {
    let origin: AudioOrigin = .microphone

    private let reporter: CaptureStatusReporter
    /// Serialises sample processing; `converter`, `assembler` and `silence`
    /// are only touched on it.
    private let processingQueue = DispatchQueue(label: "dev.trine.LiveCaptions.microphone", qos: .userInitiated)
    private let converter = MonoPCMConverter()
    private var assembler = AudioChunkAssembler(origin: .microphone)
    private var silence = SilenceMonitor()

    /// Guards everything below.
    private let lock = NSLock()
    private var runs = CaptureGenerations()
    private var engine: AVAudioEngine?
    private var configurationObserver: (any NSObjectProtocol)?
    private var continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?

    init(onStatus: @escaping @Sendable (AudioCaptureStatus) -> Void = { _ in }) {
        self.reporter = CaptureStatusReporter(deliver: onStatus)
    }

    /// Monotonic seconds, for the silence clock.
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error> {
        let (chunks, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(SystemAudioSource.bufferedChunkLimit)
        )
        let run = lock.withLock { () -> CaptureToken? in
            guard let run = runs.begin() else { return nil }
            self.continuation = continuation
            return run
        }
        guard let run else {
            throw AudioCaptureError.unavailable("Microphone capture is already running.")
        }
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.stop() }
        }
        let startedAt = Self.now
        processingQueue.sync {
            converter.reset()
            assembler.reset()
            silence.reset(at: startedAt)
        }
        reporter.begin(run)

        let granted = await Self.requestPermission()
        // The prompt can stay open for a long time; `stop()` may have run.
        // It already finished `chunks` and reported "stopped".
        guard lock.withLock({ runs.isCurrent(run) }) else { return chunks }
        guard granted else {
            let error = AudioCaptureError.permissionDenied(.microphone)
            guard finish(run, throwing: error) else { return chunks }
            throw error
        }
        do {
            try startEngine(for: run)
        } catch is StaleRun {
            return chunks
        } catch {
            let captureError = (error as? AudioCaptureError)
                ?? .unavailable("Could not start the microphone: \(error.localizedDescription)")
            guard finish(run, throwing: captureError) else { return chunks }
            throw captureError
        }
        reporter.send(.started, for: run)
        return chunks
    }

    func stop() async {
        let taken = lock.withLock { () -> (CaptureToken, Running?, AsyncThrowingStream<AudioChunk, any Error>.Continuation?)? in
            guard let run = runs.end() else { return nil }
            defer { continuation = nil }
            return (run, detachEngine(), continuation)
        }
        guard let taken else { return }
        let (run, running, continuation) = taken
        running?.tearDown()
        if let tail = processingQueue.sync(execute: { assembler.flush() }) {
            continuation?.yield(tail)
        }
        // Report before finishing the chunk stream, so a consumer that waits
        // for the stream to end has already been told "stopped".
        reporter.end(run, with: .stopped)
        continuation?.finish()
    }

    // MARK: Engine

    /// `start()` or a rebuild resumed after `stop()`: give up quietly.
    private struct StaleRun: Error {}

    /// An engine with its tap and configuration observer.
    private struct Running {
        let engine: AVAudioEngine
        let observer: (any NSObjectProtocol)?

        func tearDown() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Builds and starts an engine for `run` and makes it current. Throws
    /// `StaleRun` (after stopping the new engine) if `run` ended meanwhile.
    private func startEngine(for run: CaptureToken) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let device = AudioDevices.builtInInputDeviceID(), let unit = input.audioUnit {
            var deviceID = device
            // Falls back to the default input if this fails.
            _ = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.unavailable("No microphone input is available.")
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            self?.process(buffer, for: run)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        let engineID = ObjectIdentifier(engine)
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.configurationChanged(engine: engineID, for: run)
        }
        let running = Running(engine: engine, observer: observer)
        let accepted = lock.withLock { () -> Bool in
            // Only one engine per run: a second rebuild racing this one loses.
            guard runs.isCurrent(run), self.engine == nil else { return false }
            self.engine = engine
            configurationObserver = observer
            return true
        }
        guard accepted else {
            running.tearDown()
            throw StaleRun()
        }
    }

    /// Takes the engine out of the source. Call under `lock`.
    private func detachEngine() -> Running? {
        defer {
            engine = nil
            configurationObserver = nil
        }
        guard let engine else { return nil }
        return Running(engine: engine, observer: configurationObserver)
    }

    /// The input format of `engine` changed (device plugged in or out):
    /// rebuild it, unless the run ended or the engine was already replaced.
    private func configurationChanged(engine changed: ObjectIdentifier, for run: CaptureToken) {
        let running = lock.withLock { () -> Running? in
            guard runs.isCurrent(run), let engine, ObjectIdentifier(engine) == changed else { return nil }
            return detachEngine()
        }
        guard let running else { return }
        running.tearDown()
        processingQueue.sync { converter.reset() }
        do {
            try startEngine(for: run)
        } catch is StaleRun {
            return
        } catch {
            finish(run, throwing: .interrupted("The microphone stopped after an audio device change."))
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer, for run: CaptureToken) {
        processingQueue.sync {
            // A tap of a stopped run's engine may still fire once or twice.
            guard let continuation = lock.withLock({ runs.isCurrent(run) ? self.continuation : nil }),
                  let samples = try? converter.convert(buffer),
                  !samples.isEmpty
            else { return }
            let chunks = assembler.append(samples)
            let silenceEvent = silence.process(AudioLevel(samples: samples), at: Self.now)
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let silenceEvent {
                reporter.send(silenceEvent, for: run)
            }
        }
    }

    /// Ends `run` with `error` and reports it. Returns `false` and does
    /// nothing if `run` already ended (`stop()` got there first).
    @discardableResult
    private func finish(_ run: CaptureToken, throwing error: AudioCaptureError) -> Bool {
        let taken = lock.withLock { () -> (Running?, AsyncThrowingStream<AudioChunk, any Error>.Continuation?)? in
            guard runs.end(run) else { return nil }
            defer { continuation = nil }
            return (detachEngine(), continuation)
        }
        guard let taken else { return false }
        let (running, continuation) = taken
        running?.tearDown()
        reporter.end(run, with: error.event)
        continuation?.finish(throwing: error)
        return true
    }
}

/// Core Audio device lookups.
enum AudioDevices {
    /// The built-in microphone, if the Mac has one.
    static func builtInInputDeviceID() -> AudioDeviceID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return nil }
        return devices.first { inputChannelCount(of: $0) > 0 && isBuiltIn($0) }
    }

    private static func inputChannelCount(of device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + $1.mNumberChannels }
    }

    private static func isBuiltIn(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        return status == noErr && transport == kAudioDeviceTransportTypeBuiltIn
    }
}
