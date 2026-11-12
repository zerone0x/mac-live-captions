// Adapted from Audicap (`MicCapture` and `builtInInputDeviceID()` in AudicapApp.swift),
// https://github.com/ShinoKana/audicap
// Copyright (c) 2026 ShinoKana. MIT License, see THIRD_PARTY_NOTICES.md.

import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import LiveCaptionsCore

/// Captures the built-in microphone with `AVAudioEngine`. Off by default: the
/// user turns it on explicitly to caption their own voice.
///
/// Binds the built-in microphone instead of following the default input: when
/// Bluetooth headphones are the default input, opening their microphone drops
/// them from A2DP to the HFP call profile and playback quality falls apart.
/// Rebuilds the engine when the audio configuration changes (headphones
/// plugged in or out).
final class MicrophoneAudioSource: AudioSource, @unchecked Sendable {
    let origin: AudioOrigin = .microphone

    private let onStatus: @Sendable (AudioCaptureStatus) -> Void
    /// Serialises sample processing; `converter`, `assembler` and `silence`
    /// are only touched on it.
    private let processingQueue = DispatchQueue(label: "dev.trine.LiveCaptions.microphone", qos: .userInitiated)
    private let converter = MonoPCMConverter()
    private var assembler = AudioChunkAssembler(origin: .microphone)
    private var silence = SilenceMonitor()

    /// Guards everything below.
    private let lock = NSLock()
    private var status: AudioCaptureStatus = .idle
    private var engine: AVAudioEngine?
    private var configurationObserver: (any NSObjectProtocol)?
    private var continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?

    init(onStatus: @escaping @Sendable (AudioCaptureStatus) -> Void = { _ in }) {
        self.onStatus = onStatus
    }

    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error> {
        let (chunks, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(SystemAudioSource.bufferedChunkLimit)
        )
        let alreadyRunning = lock.withLock { () -> Bool in
            guard self.continuation == nil else { return true }
            self.continuation = continuation
            return false
        }
        guard !alreadyRunning else {
            throw AudioCaptureError.unavailable("Microphone capture is already running.")
        }
        processingQueue.sync {
            converter.reset()
            assembler.reset()
            silence.reset()
        }
        send(.startRequested)

        guard await Self.requestPermission() else {
            let error = AudioCaptureError.permissionDenied(.microphone)
            finish(throwing: error)
            throw error
        }
        do {
            try startEngine()
        } catch {
            let captureError = (error as? AudioCaptureError)
                ?? .unavailable("Could not start the microphone: \(error.localizedDescription)")
            finish(throwing: captureError)
            throw captureError
        }
        send(.started)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.stop() }
        }
        return chunks
    }

    func stop() async {
        guard let continuation = lock.withLock({ () -> AsyncThrowingStream<AudioChunk, any Error>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }) else { return }
        stopEngine()
        if let tail = processingQueue.sync(execute: { assembler.flush() }) {
            continuation.yield(tail)
        }
        continuation.finish()
        send(.stopped)
    }

    // MARK: Engine

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

    private func startEngine() throws {
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
            self?.process(buffer)
        }
        try engine.start()

        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.configurationChanged()
        }
        lock.withLock {
            self.engine = engine
            configurationObserver = observer
        }
    }

    private func stopEngine() {
        let (engine, observer) = lock.withLock { () -> (AVAudioEngine?, (any NSObjectProtocol)?) in
            defer {
                self.engine = nil
                configurationObserver = nil
            }
            return (self.engine, configurationObserver)
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// The input format changed (device plugged in or out): rebuild the engine.
    private func configurationChanged() {
        guard lock.withLock({ continuation != nil }) else { return }
        stopEngine()
        processingQueue.sync { converter.reset() }
        do {
            try startEngine()
        } catch {
            finish(throwing: .interrupted("The microphone stopped after an audio device change."))
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        processingQueue.sync {
            guard let samples = try? converter.convert(buffer), !samples.isEmpty else { return }
            let chunks = assembler.append(samples)
            let silenceEvent = silence.process(
                AudioLevel(samples: samples),
                duration: Double(samples.count) / CaptureFormat.sampleRate
            )
            let continuation = lock.withLock { self.continuation }
            for chunk in chunks {
                continuation?.yield(chunk)
            }
            if let silenceEvent {
                send(silenceEvent)
            }
        }
    }

    private func finish(throwing error: AudioCaptureError) {
        let continuation = lock.withLock { () -> AsyncThrowingStream<AudioChunk, any Error>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }
        stopEngine()
        send(error.event)
        continuation?.finish(throwing: error)
    }

    private func send(_ event: AudioCaptureEvent) {
        let changed = lock.withLock { () -> AudioCaptureStatus? in
            let next = status.applying(event)
            guard next != status else { return nil }
            status = next
            return next
        }
        if let changed {
            onStatus(changed)
        }
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
