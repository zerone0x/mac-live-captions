// Adapted from Audicap (`SCKCapture` and `screenRecordingGranted()` in AudicapApp.swift),
// https://github.com/ShinoKana/audicap
// Copyright (c) 2026 ShinoKana. MIT License, see THIRD_PARTY_NOTICES.md.

import AVFoundation
import CoreAudio
import CoreGraphics
import CoreMedia
import Foundation
import LiveCaptionsAudio
import LiveCaptionsCore
import ScreenCaptureKit

/// Captures the audio every app on this Mac plays, with ScreenCaptureKit
/// (see docs/DECISIONS.md, 0005).
///
/// Delivers mono Float32 16 kHz `AudioChunk`s of 100 ms. The capture callback
/// never blocks: chunks go into a bounded stream that drops the oldest audio if
/// the consumer falls far behind.
///
/// Status changes (permission, silence, reconnects) are reported through
/// `onStatus` on an arbitrary thread, one call at a time and in order.
/// `onStatus` must return quickly and must not call back into the source.
///
/// Every run (from `start()` to `stop()` or a final error) has a
/// `CaptureToken`; each path that resumes later (after an `await`, a
/// reconnect delay, a device-change check, a sample callback) checks it first,
/// so nothing from a stopped run can start a stream, install a listener or
/// report a status (DECISIONS 0013). If `stop()` runs while `start()` is
/// still starting, `start()` returns a stream that is already finished.
final class SystemAudioSource: NSObject, AudioSource, @unchecked Sendable {
    let origin: AudioOrigin = .system

    /// Chunks buffered for a slow consumer before the oldest are dropped (60 s).
    static let bufferedChunkLimit = 600
    /// After the default output device changes, rebuild the stream if no
    /// buffer arrives within this many seconds. ScreenCaptureKit normally
    /// keeps running across device changes (Audicap measured no lost words).
    static let deviceChangeGracePeriod: TimeInterval = 4
    /// How often "no audio" is checked when no buffers arrive at all.
    static let silenceCheckInterval: TimeInterval = 0.5

    private let reporter: CaptureStatusReporter
    private let retryPolicy: CaptureRetryPolicy
    /// Sample handler queue. `converter`, `assembler` and `silence` are only
    /// touched on it.
    private let sampleQueue = DispatchQueue(label: "dev.trine.LiveCaptions.system-audio", qos: .userInitiated)
    private let converter = MonoPCMConverter()
    private var assembler = AudioChunkAssembler(origin: .system)
    private var silence = SilenceMonitor()

    /// Guards everything below.
    private let lock = NSLock()
    private var runs = CaptureGenerations()
    private var stream: SCStream?
    private var continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?
    private var retry: CaptureRetryTracker
    private var retryTask: Task<Void, Never>?
    private var bufferCount = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var silenceTimer: (any DispatchSourceTimer)?

    init(
        retryPolicy: CaptureRetryPolicy = CaptureRetryPolicy(),
        onStatus: @escaping @Sendable (AudioCaptureStatus) -> Void = { _ in }
    ) {
        self.retryPolicy = retryPolicy
        self.retry = CaptureRetryTracker(policy: retryPolicy)
        self.reporter = CaptureStatusReporter(deliver: onStatus)
        super.init()
    }

    /// Whether the Screen & System Audio Recording permission is granted.
    ///
    /// The answer only changes after the app is relaunched: macOS refreshes
    /// the grant for a running process only on the next launch.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Monotonic seconds, for the silence and retry clocks.
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: AudioSource

    func start() async throws -> AsyncThrowingStream<AudioChunk, any Error> {
        let (chunks, continuation) = AsyncThrowingStream<AudioChunk, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.bufferedChunkLimit)
        )
        let run = lock.withLock { () -> CaptureToken? in
            guard let run = runs.begin() else { return nil }
            self.continuation = continuation
            retry = CaptureRetryTracker(policy: retryPolicy)
            bufferCount = 0
            return run
        }
        guard let run else {
            throw AudioCaptureError.unavailable("System audio capture is already running.")
        }
        continuation.onTermination = { [weak self] termination in
            // Only a consumer that stops listening stops capture; a stream we
            // finished ourselves is already stopped.
            guard case .cancelled = termination else { return }
            Task { await self?.stop() }
        }
        let startedAt = Self.now
        sampleQueue.sync {
            converter.reset()
            assembler.reset()
            silence.reset(at: startedAt)
        }
        reporter.begin(run)

        guard Self.hasPermission else {
            // Shows the system prompt the first time; later it only reports
            // "denied". Either way the grant takes effect after a relaunch.
            _ = CGRequestScreenCaptureAccess()
            let error = AudioCaptureError.permissionDenied(.system)
            guard finish(run, throwing: error) else { return chunks }
            throw error
        }

        do {
            try await startStream(for: run)
        } catch is StaleRun {
            // `stop()` ran while the stream was starting and finished `chunks`.
            return chunks
        } catch {
            let captureError = Self.captureError(for: error)
            guard finish(run, throwing: captureError) else { return chunks }
            throw captureError
        }
        reporter.send(.started, for: run)
        installDeviceListener(for: run)
        startSilenceTimer(for: run)
        return chunks
    }

    func stop() async {
        let taken = lock.withLock { () -> Detached? in
            guard let run = runs.end() else { return nil }
            return detachAll(run)
        }
        guard let taken else { return }
        taken.release()
        if let stream = taken.stream {
            try? await stream.stopCapture()
        }
        if let tail = sampleQueue.sync(execute: { assembler.flush() }) {
            taken.continuation?.yield(tail)
        }
        // Report before finishing the chunk stream, so a consumer that waits
        // for the stream to end has already been told "stopped".
        reporter.end(taken.run, with: .stopped)
        taken.continuation?.finish()
    }

    // MARK: Stream lifecycle

    /// `start()` or a reconnect resumed after `stop()`: give up quietly.
    private struct StaleRun: Error {}

    /// Starts a stream for `run` and makes it current. Throws `StaleRun` (and
    /// stops the new stream) if `run` ended meanwhile.
    private func startStream(for run: CaptureToken) async throws {
        let content = try await SCShareableContent.current
        guard lock.withLock({ runs.isCurrent(run) }) else { throw StaleRun() }
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

        let startedAt = Self.now
        let accepted = lock.withLock { () -> Bool in
            // A newer stream may also have been started for this run (a
            // device-change restart racing a reconnect); keep only one.
            guard runs.isCurrent(run), self.stream == nil else { return false }
            self.stream = stream
            retry.streamStarted(at: startedAt)
            return true
        }
        guard accepted else {
            try? await stream.stopCapture()
            throw StaleRun()
        }
        sampleQueue.sync { silence.reset(at: startedAt) }
    }

    /// Handles an unexpected end of the stream of `run`: reconnect with
    /// backoff, or finish the chunk stream with an explicit error.
    private func handleFailure(_ error: any Error, for run: CaptureToken) {
        let captureError = Self.captureError(for: error)
        if case .permissionDenied = captureError {
            // Retrying would only show the system prompt again.
            finish(run, throwing: captureError)
            return
        }
        let failedAt = Self.now
        let decision = lock.withLock { () -> CaptureRetryTracker.Decision? in
            guard runs.isCurrent(run) else { return nil }
            return retry.streamFailed(at: failedAt)
        }
        switch decision {
        case nil:
            return
        case .giveUp:
            finish(run, throwing: AudioCaptureError.interrupted(captureError.localizedDescription))
        case .retry(let attempt, let delay):
            reporter.send(.interrupted(attempt: attempt), for: run)
            let task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.reconnect(run)
            }
            let current = lock.withLock { () -> Bool in
                guard runs.isCurrent(run) else { return false }
                retryTask = task
                return true
            }
            if !current {
                task.cancel()
            }
        }
    }

    private func reconnect(_ run: CaptureToken) async {
        guard lock.withLock({ runs.isCurrent(run) }) else { return }
        do {
            try await startStream(for: run)
            reporter.send(.started, for: run)
        } catch is StaleRun {
            return
        } catch {
            handleFailure(error, for: run)
        }
    }

    /// Stops the current stream of `run` and starts a new one, for a stream
    /// that went quiet after a device change. Not counted as a failure.
    private func restart(_ run: CaptureToken) async {
        let stream = lock.withLock { () -> SCStream? in
            guard runs.isCurrent(run) else { return nil }
            defer { self.stream = nil }
            return self.stream
        }
        guard let stream else { return }
        try? await stream.stopCapture()
        await reconnect(run)
    }

    /// Ends `run` with `error` and reports it. Returns `false` and does
    /// nothing if `run` already ended (`stop()` got there first).
    @discardableResult
    private func finish(_ run: CaptureToken, throwing error: AudioCaptureError) -> Bool {
        let taken = lock.withLock { () -> Detached? in
            guard runs.end(run) else { return nil }
            return detachAll(run)
        }
        guard let taken else { return false }
        taken.release()
        // Normally nil here: failures clear the stream before they get here.
        taken.stream?.stopCapture { _ in }
        reporter.end(run, with: error.event)
        taken.continuation?.finish(throwing: error)
        return true
    }

    /// Everything a run holds, taken out of the source in one step.
    private struct Detached {
        let run: CaptureToken
        let stream: SCStream?
        let continuation: AsyncThrowingStream<AudioChunk, any Error>.Continuation?
        let retryTask: Task<Void, Never>?
        let deviceListener: AudioObjectPropertyListenerBlock?
        let silenceTimer: (any DispatchSourceTimer)?
        let sampleQueue: DispatchQueue

        /// Cancels the pending reconnect, the silence timer and the device
        /// listener.
        func release() {
            retryTask?.cancel()
            silenceTimer?.cancel()
            if let deviceListener {
                SystemAudioSource.removeDeviceListener(deviceListener, queue: sampleQueue)
            }
        }
    }

    /// Takes everything out of the source. Call under `lock`.
    private func detachAll(_ run: CaptureToken) -> Detached {
        defer {
            stream = nil
            continuation = nil
            retryTask = nil
            deviceListener = nil
            silenceTimer = nil
        }
        return Detached(
            run: run,
            stream: stream,
            continuation: continuation,
            retryTask: retryTask,
            deviceListener: deviceListener,
            silenceTimer: silenceTimer,
            sampleQueue: sampleQueue
        )
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

    // MARK: No audio

    /// Checks for "no audio" on a timer as well as on every buffer, so it is
    /// detected even if ScreenCaptureKit sends no buffers while nothing plays.
    private func startSilenceTimer(for run: CaptureToken) {
        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(
            deadline: .now() + Self.silenceCheckInterval,
            repeating: Self.silenceCheckInterval,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            // Runs on `sampleQueue`.
            guard let self, lock.withLock({ runs.isCurrent(run) }) else { return }
            if let event = silence.check(at: Self.now) {
                reporter.send(event, for: run)
            }
        }
        // Resume before storing: releasing a suspended dispatch source crashes.
        // The handler checks the token, so an early tick does nothing wrong.
        timer.resume()
        let current = lock.withLock { () -> Bool in
            guard runs.isCurrent(run) else { return false }
            silenceTimer = timer
            return true
        }
        if !current {
            timer.cancel()
        }
    }

    // MARK: Output device changes

    private func installDeviceListener(for run: CaptureToken) {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.defaultOutputDeviceChanged(for: run)
        }
        var address = Self.defaultOutputDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, sampleQueue, listener
        )
        guard status == noErr else { return }
        let installed = lock.withLock { () -> Bool in
            // `stop()` ran after the listener was added: it could not see it.
            guard runs.isCurrent(run) else { return false }
            deviceListener = listener
            return true
        }
        if !installed {
            Self.removeDeviceListener(listener, queue: sampleQueue)
        }
    }

    private static func removeDeviceListener(_ listener: @escaping AudioObjectPropertyListenerBlock, queue: DispatchQueue) {
        var address = defaultOutputDeviceAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, listener
        )
    }

    /// ScreenCaptureKit usually keeps delivering after a device change. If no
    /// buffer at all arrives within the grace period, rebuild the stream.
    ///
    /// No buffers can also mean ScreenCaptureKit sends nothing while nothing
    /// plays; then the rebuild costs a short reconnect and loses no audio, so
    /// the check does not need to tell the two apart (DECISIONS 0013).
    private func defaultOutputDeviceChanged(for run: CaptureToken) {
        let countAtChange = lock.withLock { bufferCount }
        sampleQueue.asyncAfter(deadline: .now() + Self.deviceChangeGracePeriod) { [weak self] in
            guard let self else { return }
            let stalled = lock.withLock {
                runs.isCurrent(run) && stream != nil && bufferCount == countAtChange
            }
            if stalled {
                Task { await self.restart(run) }
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
        guard type == .audio else { return }
        // Called on `sampleQueue`. Buffers of a stream that is no longer
        // current (stopped, replaced, or from an older run) are dropped.
        let current = lock.withLock { () -> (CaptureToken, AsyncThrowingStream<AudioChunk, any Error>.Continuation?)? in
            guard self.stream === stream, let run = runs.current else { return nil }
            bufferCount += 1
            return (run, self.continuation)
        }
        guard let current,
              let buffer = makePCMBuffer(from: sampleBuffer),
              let samples = try? converter.convert(buffer),
              !samples.isEmpty
        else { return }
        let (run, continuation) = current

        let chunks = assembler.append(samples)
        let silenceEvent = silence.process(AudioLevel(samples: samples), at: Self.now)
        for chunk in chunks {
            continuation?.yield(chunk)
        }
        if let silenceEvent {
            reporter.send(silenceEvent, for: run)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let run = lock.withLock { () -> CaptureToken? in
            guard self.stream === stream, let run = runs.current else { return nil }
            self.stream = nil
            return run
        }
        guard let run else { return }
        handleFailure(error, for: run)
    }
}
