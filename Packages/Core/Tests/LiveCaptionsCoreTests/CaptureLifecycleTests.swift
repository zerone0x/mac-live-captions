import Foundation
import Synchronization
import Testing
@testable import LiveCaptionsCore

@Suite("Capture lifecycle")
struct CaptureLifecycleTests {
    // MARK: Generations

    @Test("a second start while running is refused")
    func refusesSecondStart() {
        var generations = CaptureGenerations()
        let first = generations.begin()
        #expect(first != nil)
        #expect(generations.begin() == nil)
        #expect(generations.isActive)
    }

    @Test("stop during start: the starting run's token is stale, even after a restart")
    func stopDuringStartMakesTokenStale() throws {
        var generations = CaptureGenerations()
        let starting = try begun(&generations)
        // stop() runs while start() awaits a permission prompt or the stream.
        #expect(generations.end() == starting)
        #expect(!generations.isCurrent(starting))
        // start() again before the first start() resumes.
        let restarted = try begun(&generations)
        #expect(restarted != starting)
        #expect(!generations.isCurrent(starting), "the first start() must not install anything")
        #expect(generations.isCurrent(restarted))
    }

    @Test("a stale reconnect or error path cannot end a newer run")
    func staleEndIsIgnored() throws {
        var generations = CaptureGenerations()
        let old = try begun(&generations)
        _ = generations.end()
        let new = try begun(&generations)
        let endedOld = generations.end(old)
        #expect(!endedOld)
        #expect(generations.isCurrent(new))
        let endedNew = generations.end(new)
        #expect(endedNew)
        #expect(!generations.isActive)
        #expect(generations.end() == nil, "stop() when stopped does nothing")
    }

    @Test("tokens never repeat over many runs")
    func tokensAreUnique() {
        var generations = CaptureGenerations()
        var seen = Set<CaptureToken>()
        for _ in 0..<1_000 {
            guard let token = generations.begin() else {
                Issue.record("begin failed after end")
                return
            }
            #expect(seen.insert(token).inserted)
            _ = generations.end()
        }
    }

    // MARK: Retry

    @Test("a stream that dies right after starting does not reset the count, so retries end")
    func fastFailuresGiveUp() {
        var tracker = CaptureRetryTracker(policy: CaptureRetryPolicy(maxAttempts: 3))
        var now: TimeInterval = 0
        tracker.streamStarted(at: now)
        var decisions: [CaptureRetryTracker.Decision] = []
        for _ in 0..<4 {
            now += 0.5
            let decision = tracker.streamFailed(at: now)
            decisions.append(decision)
            if case .retry(_, let delay) = decision {
                // The reconnect succeeds, and the new stream dies 0.5 s later.
                now += delay
                tracker.streamStarted(at: now)
            }
        }
        #expect(decisions == [
            .retry(attempt: 1, delay: 2),
            .retry(attempt: 2, delay: 4),
            .retry(attempt: 3, delay: 8),
            .giveUp(attempts: 3),
        ])
    }

    @Test("a stream that stayed up for the healthy period starts counting from 1 again")
    func healthyStreamResetsCount() {
        var tracker = CaptureRetryTracker(healthyDuration: 10)
        tracker.streamStarted(at: 0)
        #expect(tracker.streamFailed(at: 1) == .retry(attempt: 1, delay: 2))
        tracker.streamStarted(at: 3)
        #expect(tracker.streamFailed(at: 4) == .retry(attempt: 2, delay: 4))
        tracker.streamStarted(at: 8)
        // Up for exactly 10 s: healthy.
        #expect(tracker.streamFailed(at: 18) == .retry(attempt: 1, delay: 2))
        #expect(tracker.attempt == 1)
    }

    @Test("just under the healthy period still counts as a failed attempt")
    func almostHealthyDoesNotReset() {
        var tracker = CaptureRetryTracker(healthyDuration: 10)
        tracker.streamStarted(at: 0)
        #expect(tracker.streamFailed(at: 1) == .retry(attempt: 1, delay: 2))
        tracker.streamStarted(at: 3)
        #expect(tracker.streamFailed(at: 12.9) == .retry(attempt: 2, delay: 4))
    }

    @Test("failed reconnects (no stream started) keep counting up")
    func failedReconnectsCount() {
        var tracker = CaptureRetryTracker(policy: CaptureRetryPolicy(maxAttempts: 2), healthyDuration: 10)
        tracker.streamStarted(at: 0)
        #expect(tracker.streamFailed(at: 100) == .retry(attempt: 1, delay: 2))
        // The reconnect itself throws 50 s later: no stream was up, no reset.
        #expect(tracker.streamFailed(at: 150) == .retry(attempt: 2, delay: 4))
        #expect(tracker.streamFailed(at: 200) == .giveUp(attempts: 2))
    }

    // MARK: Status reporter

    @Test("reports start, capture and stop once each, in order")
    func reporterHappyPath() throws {
        var generations = CaptureGenerations()
        let recorder = StatusRecorder()
        let reporter = CaptureStatusReporter(deliver: recorder.record)
        let run = try begun(&generations)
        reporter.begin(run)
        reporter.send(.started, for: run)
        reporter.send(.started, for: run)
        reporter.send(.silenceDetected, for: run)
        reporter.end(run, with: .stopped)
        #expect(recorder.statuses == [.starting, .capturing, .noAudio, .idle])
        #expect(reporter.status == .idle)
    }

    @Test("nothing from a run is reported after it stopped")
    func reporterDropsAfterEnd() throws {
        var generations = CaptureGenerations()
        let recorder = StatusRecorder()
        let reporter = CaptureStatusReporter(deliver: recorder.record)
        let run = try begun(&generations)
        reporter.begin(run)
        reporter.send(.started, for: run)
        reporter.end(run, with: .stopped)
        // A sample callback or reconnect task of the stopped run, late.
        reporter.send(.silenceDetected, for: run)
        reporter.send(.interrupted(attempt: 1), for: run)
        reporter.send(.started, for: run)
        reporter.end(run, with: .failed("late"))
        #expect(recorder.statuses == [.starting, .capturing, .idle])
        #expect(reporter.status == .idle)
    }

    @Test("events of an older run cannot change a newer run's status")
    func reporterDropsStaleRun() throws {
        var generations = CaptureGenerations()
        let recorder = StatusRecorder()
        let reporter = CaptureStatusReporter(deliver: recorder.record)
        let old = try begun(&generations)
        reporter.begin(old)
        reporter.send(.started, for: old)
        _ = generations.end()
        let new = try begun(&generations)
        // The new run opens before the old stop() got to report.
        reporter.begin(new)
        reporter.end(old, with: .stopped)
        reporter.send(.silenceDetected, for: old)
        reporter.send(.started, for: new)
        #expect(recorder.statuses == [.starting, .capturing, .starting, .capturing])
        #expect(reporter.status == .capturing)
    }

    @Test("a new run starts from 'starting' even if the old one never reported its end")
    func reporterBeginResets() throws {
        var generations = CaptureGenerations()
        let reporter = CaptureStatusReporter(deliver: { _ in })
        let old = try begun(&generations)
        reporter.begin(old)
        reporter.send(.started, for: old)
        _ = generations.end()
        let new = try begun(&generations)
        reporter.begin(new)
        #expect(reporter.status == .starting)
    }

    @Test("a status being delivered is not overtaken by a stop on another thread")
    func reporterDeliversInApplyOrder() throws {
        var generations = CaptureGenerations()
        let run = try begun(&generations)
        let recorder = StatusRecorder()
        let stopDone = DispatchSemaphore(value: 0)
        let reporterBox = Mutex<CaptureStatusReporter?>(nil)
        let reporter = CaptureStatusReporter { status in
            if status == .noAudio {
                // While "No audio" is on its way to the UI, stop() runs on
                // another thread. It must wait until this delivery is done.
                let reporter = reporterBox.withLock { $0 }
                Thread.detachNewThread {
                    reporter?.end(run, with: .stopped)
                    stopDone.signal()
                }
                _ = stopDone.wait(timeout: .now() + 0.3)
            }
            recorder.record(status)
        }
        reporterBox.withLock { $0 = reporter }
        reporter.begin(run)
        reporter.send(.started, for: run)
        reporter.send(.silenceDetected, for: run)
        // The stop thread may still be waiting for the lock.
        _ = stopDone.wait(timeout: .now() + 5)
        #expect(recorder.statuses == [.starting, .capturing, .noAudio, .idle])
        #expect(recorder.statuses.last == reporter.status)
    }

    @Test("concurrent events: the last status delivered is always the reporter's status")
    func reporterConcurrentConsistency() throws {
        for _ in 0..<50 {
            var generations = CaptureGenerations()
            let run = try begun(&generations)
            let recorder = StatusRecorder()
            let reporter = CaptureStatusReporter(deliver: recorder.record)
            reporter.begin(run)
            reporter.send(.started, for: run)
            DispatchQueue.concurrentPerform(iterations: 64) { index in
                switch index % 4 {
                case 0: reporter.send(.silenceDetected, for: run)
                case 1: reporter.send(.soundDetected, for: run)
                case 2: reporter.send(.interrupted(attempt: index), for: run)
                default: reporter.send(.started, for: run)
                }
                if index == 40 { reporter.end(run, with: .stopped) }
            }
            #expect(recorder.statuses.last == .idle)
            #expect(reporter.status == .idle)
            // Each delivered status differs from the one before it.
            for (previous, next) in zip(recorder.statuses, recorder.statuses.dropFirst()) {
                #expect(previous != next)
            }
        }
    }
}

/// Starts a run, failing the test if one was already active.
private func begun(_ generations: inout CaptureGenerations) throws -> CaptureToken {
    let token = generations.begin()
    return try #require(token)
}

/// Collects delivered statuses from any thread.
private final class StatusRecorder: Sendable {
    private let storage = Mutex<[AudioCaptureStatus]>([])

    var statuses: [AudioCaptureStatus] { storage.withLock { $0 } }

    var record: @Sendable (AudioCaptureStatus) -> Void {
        { [self] status in storage.withLock { $0.append(status) } }
    }
}
