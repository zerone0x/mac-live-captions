import Testing
@testable import LiveCaptionsCore

@Suite("SessionPhase")
struct SessionPhaseTests {
    @Test("happy path: start, run, stop")
    func happyPath() {
        var phase = SessionPhase.idle
        phase = phase.applying(.startRequested)
        #expect(phase == .starting)
        phase = phase.applying(.didStart)
        #expect(phase == .running)
        phase = phase.applying(.stopRequested)
        #expect(phase == .stopping)
        phase = phase.applying(.didStop)
        #expect(phase == .idle)
    }

    @Test("a failure while running is shown and allows a restart")
    func failureThenRestart() {
        let failed = SessionPhase.running.applying(.didFail("Audio source ended"))
        #expect(failed == .failed(message: "Audio source ended"))
        #expect(failed.canStart)
        #expect(!failed.canStop)
        #expect(failed.statusText == "Error: Audio source ended")
        #expect(failed.applying(.startRequested) == .starting)
    }

    @Test(
        "events that make no sense in a phase are ignored",
        arguments: [
            (SessionPhase.idle, SessionEvent.stopRequested),
            (.idle, .didStart),
            (.idle, .didStop),
            (.idle, .didFail("x")),
            (.running, .startRequested),
            (.running, .didStart),
            (.stopping, .startRequested),
            (.stopping, .stopRequested),
            (.failed(message: "x"), .stopRequested),
            (.failed(message: "x"), .didStop),
        ]
    )
    func ignoredEvents(phase: SessionPhase, event: SessionEvent) {
        #expect(phase.applying(event) == phase)
    }

    @Test(
        "Start and Stop enablement",
        arguments: [
            (SessionPhase.idle, true, false),
            (.starting, false, true),
            (.running, false, true),
            (.stopping, false, false),
            (.failed(message: "x"), true, false),
        ]
    )
    func enablement(phase: SessionPhase, canStart: Bool, canStop: Bool) {
        #expect(phase.canStart == canStart)
        #expect(phase.canStop == canStop)
    }
}
