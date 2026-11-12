// Adapted from Audicap (`SCKCapture` and `screenRecordingGranted()` in AudicapApp.swift),
// https://github.com/ShinoKana/audicap
// Copyright (c) 2026 ShinoKana. MIT License, see THIRD_PARTY_NOTICES.md.

import AVFoundation
import CoreAudio
import CoreGraphics
import CoreMedia
import Foundation
import LiveCaptionsCore
import ScreenCaptureKit

/// Captures the audio every app on this Mac plays, with ScreenCaptureKit
/// (see docs/DECISIONS.md, 0005).
///
/// Delivers mono Float32 16 kHz `AudioChunk`s of 100 ms. The capture callback
/// never blocks: chunks go into a bounded stream that drops the oldest audio if
/// the consumer falls far behind. Status changes (permission, silence,
/// reconnects) are reported through `onStatus`, on an arbitrary thread.
final class SystemAudioSource: NSObject, AudioSource, @unchecked Sendable {
    let origin: AudioOrigin = .system

    /// Chunks buffered for a slow consumer before the oldest are dropped (60 s).
    static let bufferedChunkLimit = 600
    /// After the default output device changes, rebuild the stream if no audio
    /// arrives within this many seconds. ScreenCaptureKit normally keeps
    /// running across device changes (Audicap measured no lost words).
    static let deviceChangeGracePeriod: TimeInterval = 4

    private let onStatus: @Sendable (AudioCaptureStatus) -> Void
    private let retryPolicy: CaptureRetryPolicy
    /// Sample handler queue. `converter`, `assembler` and `silence` are only
    /// touched on it.
    private let sampleQueue = DispatchQueue(label: "dev.trine.LiveCaptions.system-audio", qos: .userInitiated)
    private let converter = MonoPCMConverter()
    private var assembler = AudioChunkAssembler(origin: .system)
    private var silence = SilenceMonitor()

    /// Guards everything below.
    private let lock = NSLock()
    private var status: AudioCaptureStatus = .idle
    private var stream: SCStream?
    private var continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?
    private var isStopping = false
    private var retryAttempt = 0
    private var bufferCount = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?

    init(
        retryPolicy: CaptureRetryPolicy = CaptureRetryPolicy(),
        onStatus: @escaping @Sendable (AudioCaptureStatus) -> Void = { _ in }
    ) {
        self.retryPolicy = retryPolicy
        self.onStatus = onStatus
        super.init()
    }

    /// Whether the Screen & System Audio Recording permission is granted.
    ///
    /// The answer only changes after the app is relaunched: macOS refreshes
    /// the grant for a running process only on the next launch.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    // MARK: AudioSource

    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error> {
        let (chunks, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.bufferedChunkLimit)
        )
        let alreadyRunning = lock.withLock { () -> Bool in
            guard self.continuation == nil else { return true }
            self.continuation = continuation
            isStopping = false
            retryAttempt = 0
            bufferCount = 0
            return false
        }
        guard !alreadyRunning else {
            throw AudioCaptureError.unavailable("System audio capture is already running.")
        }
        sampleQueue.sync {
            converter.reset()
            assembler.reset()
            silence.reset()
        }
        send(.startRequested)

        guard Self.hasPermission else {
            // Shows the system prompt the first time; later it only reports
            // "denied". Either way the grant takes effect after a relaunch.
            _ = CGRequestScreenCaptureAccess()
            let error = AudioCaptureError.permissionDenied(.system)
            finish(throwing: error)
            throw error
        }

        do {
            try await startStream()
        } catch {
            let captureError = Self.captureError(for: error)
            finish(throwing: captureError)
            throw captureError
        }
        send(.started)
        installDeviceListener()
        continuation.onTermination = { [weak self] termination in
            // Only a consumer that stops listening stops capture; a stream we
            // finished ourselves is already stopped.
            guard case .cancelled = termination else { return }
            Task { await self?.stop() }
        }
        return chunks
    }

    func stop() async {
        let (stream, continuation) = lock.withLock { () -> (SCStream?, AsyncThrowingStream<AudioChunk, any Error>.Continuation?) in
            isStopping = true
            let stream = self.stream
            let continuation = self.continuation
            self.stream = nil
            self.continuation = nil
            return (stream, continuation)
        }
        removeDeviceListener()
        if let stream {
            try? await stream.stopCapture()
        }
        guard let continuation else { return }
        if let tail = sampleQueue.sync(execute: { assembler.flush() }) {
            continuation.yield(tail)
        }
        continuation.finish()
        send(.stopped)
    }

    // MARK: Stream lifecycle

    private func startStream() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AudioCaptureError.unavailable("No display found to attach system audio capture to.")
        }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = Int(CaptureFormat.sampleRate)
        configuration.channelCount = 1
        // Never caption our own sounds.
        configuration.excludesCurrentProcessAudio = true
        // Only the audio output is registered; keep the unused video tiny and slow.
        configuration.width = 64
        configuration.height = 64
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        let stopped = lock.withLock { () -> Bool in
            guard !isStopping else { return true }
            self.stream = stream
            return false
        }
        if stopped {
            // `stop()` ran while we were starting.
            try? await stream.stopCapture()
        }
    }

    /// Handles an unexpected end of the stream: reconnect with backoff, or
    /// finish the chunk stream with an explicit error.
    private func handleFailure(_ error: any Error) {
        let captureError = Self.captureError(for: error)
        if case .permissionDenied = captureError {
            // Retrying would only show the system prompt again.
            finish(throwing: captureError)
            return
        }
        let next = lock.withLock { () -> (attempt: Int, delay: TimeInterval?)? in
            guard !isStopping else { return nil }
            retryAttempt += 1
            return (retryAttempt, retryPolicy.delay(forAttempt: retryAttempt))
        }
        guard let next else { return }
        guard let delay = next.delay else {
            finish(throwing: AudioCaptureError.interrupted(captureError.localizedDescription))
            return
        }
        send(.interrupted(attempt: next.attempt))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.reconnect()
        }
    }

    private func reconnect() async {
        guard !lock.withLock({ isStopping }) else { return }
        do {
            try await startStream()
            lock.withLock { retryAttempt = 0 }
            send(.started)
        } catch {
            handleFailure(error)
        }
    }

    /// Stops the current stream and starts a new one, for a stalled stream.
    private func restart() async {
        let stream = lock.withLock { () -> SCStream? in
            guard !isStopping else { return nil }
            let stream = self.stream
            self.stream = nil
            return stream
        }
        guard let stream else { return }
        try? await stream.stopCapture()
        await reconnect()
    }

    /// Ends the chunk stream with `error` and reports the matching status.
    private func finish(throwing error: AudioCaptureError) {
        let continuation = lock.withLock { () -> AsyncThrowingStream<AudioChunk, any Error>.Continuation? in
            let continuation = self.continuation
            self.continuation = nil
            self.stream = nil
            isStopping = true
            return continuation
        }
        removeDeviceListener()
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

    private static func captureError(for error: any Error) -> AudioCaptureError {
        if let captureError = error as? AudioCaptureError {
            return captureError
        }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
           nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied(.system)
        }
        return .unavailable(nsError.localizedDescription)
    }

    // MARK: Output device changes

    private func installDeviceListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.defaultOutputDeviceChanged()
        }
        var address = Self.defaultOutputDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, sampleQueue, listener
        )
        guard status == noErr else { return }
        lock.withLock { deviceListener = listener }
    }

    private func removeDeviceListener() {
        guard let listener = lock.withLock({ () -> AudioObjectPropertyListenerBlock? in
            defer { deviceListener = nil }
            return deviceListener
        }) else { return }
        var address = Self.defaultOutputDeviceAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, sampleQueue, listener
        )
    }

    /// ScreenCaptureKit usually keeps delivering after a device change. Only
    /// rebuild the stream if it actually went quiet (no buffers at all, which
    /// is different from buffers of silence).
    private func defaultOutputDeviceChanged() {
        let countAtChange = lock.withLock { bufferCount }
        sampleQueue.asyncAfter(deadline: .now() + Self.deviceChangeGracePeriod) { [weak self] in
            guard let self else { return }
            let stalled = lock.withLock { !isStopping && stream != nil && bufferCount == countAtChange }
            if stalled {
                Task { await self.restart() }
            }
        }
    }

    private static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

// MARK: - SCStreamOutput, SCStreamDelegate

extension SystemAudioSource: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let buffer = makePCMBuffer(from: sampleBuffer) else { return }
        // Called on `sampleQueue`.
        let samples: [Float]
        do {
            samples = try converter.convert(buffer)
        } catch {
            return
        }
        guard !samples.isEmpty else { return }

        let chunks = assembler.append(samples)
        let silenceEvent = silence.process(
            AudioLevel(samples: samples),
            duration: Double(samples.count) / CaptureFormat.sampleRate
        )
        let continuation = lock.withLock { () -> AsyncThrowingStream<AudioChunk, any Error>.Continuation? in
            bufferCount += 1
            return self.continuation
        }
        for chunk in chunks {
            continuation?.yield(chunk)
        }
        if let silenceEvent {
            send(silenceEvent)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let isCurrent = lock.withLock { () -> Bool in
            guard self.stream === stream else { return false }
            self.stream = nil
            return true
        }
        guard isCurrent else { return }
        handleFailure(error)
    }
}
