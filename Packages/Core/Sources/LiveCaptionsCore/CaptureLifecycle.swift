import Foundation
import Synchronization

// Start/stop bookkeeping shared by the capture sources (docs/DECISIONS.md, 0012).
//
// A capture source starts and stops from several places at once: `start()`
// awaits permission prompts and ScreenCaptureKit, `stop()` can run in the
// middle of that, reconnect tasks and device-change handlers fire later on
// other threads. Every one of those paths holds the `CaptureToken` of the run
// it belongs to and checks it before it changes anything, so work left over
// from a stopped run can never start, install or report anything.

/// Identifies one run of a capture source, from `start()` to `stop()` or a
/// terminal error. A new run always gets a new token.
public struct CaptureToken: Sendable, Hashable, CustomStringConvertible {
    let value: UInt64

    public var description: String { "run \(value)" }
}

/// Hands out `CaptureToken`s and remembers which run is current.
///
/// Not thread-safe on its own: keep it under the source's lock together with
/// the state it guards (stream, engine, continuation), so a token check and
/// the change it allows happen atomically.
public struct CaptureGenerations: Sendable {
    /// Token of the running capture, or `nil` when the source is stopped.
    public private(set) var current: CaptureToken?
    private var lastValue: UInt64 = 0

    public init() {}

    public var isActive: Bool { current != nil }

    /// Starts a new run. Returns `nil` if a run is already active.
    public mutating func begin() -> CaptureToken? {
        guard current == nil else { return nil }
        lastValue += 1
        let token = CaptureToken(value: lastValue)
        current = token
        return token
    }

    /// Ends the active run, whichever it is, and returns its token
    /// (`nil` if nothing was running). Used by `stop()`.
    public mutating func end() -> CaptureToken? {
        defer { current = nil }
        return current
    }

    /// Ends the run only if `token` is still current. Used by error paths
    /// that belong to one specific run.
    public mutating func end(_ token: CaptureToken) -> Bool {
        guard current == token else { return false }
        current = nil
        return true
    }

    /// Whether `token` belongs to the run that is still active.
    public func isCurrent(_ token: CaptureToken) -> Bool {
        current == token
    }
}

/// Counts reconnect attempts and decides when to give up.
///
/// The count goes back to zero only after a stream stayed up for
/// `healthyDuration`. Resetting it whenever a stream starts would let a stream
/// that dies right after starting retry at the shortest delay forever.
///
/// "Up" is measured in wall-clock time from the stream's start to its
/// failure, not in delivered buffers, so the reset works the same whether or
/// not ScreenCaptureKit sends buffers while nothing is playing.
public struct CaptureRetryTracker: Sendable {
    public enum Decision: Sendable, Hashable {
        /// Reconnect attempt `attempt` (1-based) after `delay` seconds.
        case retry(attempt: Int, delay: TimeInterval)
        /// Reconnecting failed `attempts` times in a row; stop for good.
        case giveUp(attempts: Int)
    }

    public static let defaultHealthyDuration: TimeInterval = 10

    public let policy: CaptureRetryPolicy
    public let healthyDuration: TimeInterval
    /// Failed attempts since the last healthy stream.
    public private(set) var attempt = 0
    /// When the current stream started (monotonic seconds), if one is up.
    private var streamStartedAt: TimeInterval?

    public init(
        policy: CaptureRetryPolicy = CaptureRetryPolicy(),
        healthyDuration: TimeInterval = CaptureRetryTracker.defaultHealthyDuration
    ) {
        self.policy = policy
        self.healthyDuration = healthyDuration
    }

    /// A stream started successfully at `now` (monotonic seconds).
    public mutating func streamStarted(at now: TimeInterval) {
        streamStartedAt = now
    }

    /// The stream stopped unexpectedly, or a reconnect failed, at `now`.
    public mutating func streamFailed(at now: TimeInterval) -> Decision {
        if let startedAt = streamStartedAt, now - startedAt >= healthyDuration {
            attempt = 0
        }
        streamStartedAt = nil
        attempt += 1
        guard let delay = policy.delay(forAttempt: attempt) else {
            return .giveUp(attempts: attempt - 1)
        }
        return .retry(attempt: attempt, delay: delay)
    }
}

/// Owns a source's `AudioCaptureStatus` and reports each change exactly once,
/// in order, for the run it belongs to.
///
/// Events are applied and delivered under one lock, so two threads (the
/// sample queue reporting silence and `stop()` reporting `.stopped`) can never
/// deliver in the opposite order to the one they were applied in. Events
/// tagged with a token other than the open run's are dropped, and so is
/// anything after the run ended: a late "no audio" from a stopped stream
/// cannot overwrite "Not capturing", or a newer run's status.
///
/// `deliver` runs under the lock: it must return quickly and must not call
/// back into the reporter or the source (yield into an `AsyncStream`, for
/// example).
public final class CaptureStatusReporter: Sendable {
    private struct State {
        var status: AudioCaptureStatus = .idle
        var openRun: CaptureToken?
    }

    private let state = Mutex(State())
    private let deliver: @Sendable (AudioCaptureStatus) -> Void

    public init(deliver: @escaping @Sendable (AudioCaptureStatus) -> Void) {
        self.deliver = deliver
    }

    /// The last status reported.
    public var status: AudioCaptureStatus {
        state.withLock { $0.status }
    }

    /// Opens `run` and reports `.starting`. Replaces any run still open.
    public func begin(_ run: CaptureToken) {
        state.withLock { state in
            state.openRun = run
            update(&state, to: AudioCaptureStatus.idle.applying(.startRequested))
        }
    }

    /// Applies `event` if `run` is the open run; otherwise drops it.
    public func send(_ event: AudioCaptureEvent, for run: CaptureToken) {
        state.withLock { state in
            guard state.openRun == run else { return }
            update(&state, to: state.status.applying(event))
        }
    }

    /// Applies the last event of `run` (`.stopped` or an error) and closes it,
    /// so nothing else from that run is reported.
    public func end(_ run: CaptureToken, with event: AudioCaptureEvent) {
        state.withLock { state in
            guard state.openRun == run else { return }
            state.openRun = nil
            update(&state, to: state.status.applying(event))
        }
    }

    private func update(_ state: inout State, to next: AudioCaptureStatus) {
        guard next != state.status else { return }
        state.status = next
        deliver(next)
    }
}
