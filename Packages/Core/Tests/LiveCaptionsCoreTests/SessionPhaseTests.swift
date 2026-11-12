import Testing
@testable import LiveCaptionsCore

@Suite("SessionPhase")
struct SessionPhaseTests {
    @Test("happy path: Start checks the model, listens only once capture reports it, Stop waits for the end")
    func happyPath() {
        var phase = SessionPhase.idle

        var step = phase.transition(on: .startRequested)
        #expect(step == SessionTransition(.checkingModel, [.checkModel]))
        phase = step.phase

        step = phase.transition(on: .modelStateChanged(.ready))
        #expect(step == SessionTransition(.startingCapture, [.startPipeline]))
        phase = step.phase
        // Start alone never claims to listen.
        #expect(phase != .listening(.hearing))

        phase = phase.applying(.captureStatusChanged(.starting))
        #expect(phase == .startingCapture)
        phase = phase.applying(.captureStatusChanged(.capturing))
        #expect(phase == .listening(.hearing))

        step = phase.transition(on: .stopRequested)
        #expect(step == SessionTransition(.stopping, [.stopPipeline]))
        phase = step.phase

        // The source reports `.idle` as it stops; only the pipeline end counts.
        phase = phase.applying(.captureStatusChanged(.idle))
        #expect(phase == .stopping)
        phase = phase.applying(.pipelineEnded(failure: nil))
        #expect(phase == .idle)
    }

    @Test(
        "capture status maps onto the listening phase",
        arguments: [
            (AudioCaptureStatus.capturing, SessionPhase.listening(.hearing)),
            (.noAudio, .listening(.noAudio)),
            (.reconnecting(attempt: 2), .listening(.reconnecting(attempt: 2))),
            (.permissionDenied(.system), .permissionDenied(.system)),
            (.failed(message: "boom"), .failed(message: "boom")),
            (.starting, .listening(.hearing)),
            (.idle, .listening(.hearing)),
        ]
    )
    func captureMapping(status: AudioCaptureStatus, expected: SessionPhase) {
        let phase = SessionPhase.listening(.hearing).applying(.captureStatusChanged(status))
        #expect(phase == expected)
    }

    @Test("permission denied and capture failures stop the pipeline")
    func captureProblemsStopThePipeline() {
        let denied = SessionPhase.startingCapture.transition(on: .captureStatusChanged(.permissionDenied(.system)))
        #expect(denied.effects == [.stopPipeline])
        #expect(denied.phase.canStart)
        #expect(!denied.phase.canStop)

        let failed = SessionPhase.listening(.noAudio).transition(on: .captureStatusChanged(.failed(message: "x")))
        #expect(failed.effects == [.stopPipeline])
    }

    @Test("a permission error that ends the stream first is refined by the status")
    func permissionAfterFailure() {
        var phase = SessionPhase.startingCapture.applying(.pipelineEnded(failure: "denied"))
        #expect(phase == .failed(message: "denied"))
        phase = phase.applying(.captureStatusChanged(.permissionDenied(.system)))
        #expect(phase == .permissionDenied(.system))
    }

    @Test(
        "the model state decides whether capture starts",
        arguments: [
            (SpeechAssetState.ready, SessionPhase.startingCapture),
            (.checking, .checkingModel),
            (.notInstalled, .waitingForModel(.notInstalled)),
            (.downloading(fractionCompleted: 0.5), .waitingForModel(.downloading(fractionCompleted: 0.5))),
            (.unsupported, .waitingForModel(.unsupported)),
            (.failed(message: "x"), .waitingForModel(.failed(message: "x"))),
        ]
    )
    func modelMapping(state: SpeechAssetState, expected: SessionPhase) {
        #expect(SessionPhase.checkingModel.applying(.modelStateChanged(state)) == expected)
    }

    @Test("a waiting session starts by itself when the download finishes")
    func downloadThenStart() {
        var phase = SessionPhase.waitingForModel(.notInstalled)
        #expect(phase.canStart)
        phase = phase.applying(.modelStateChanged(.downloading(fractionCompleted: nil)))
        #expect(phase == .waitingForModel(.downloading(fractionCompleted: nil)))
        #expect(!phase.canStart)
        #expect(phase.canStop)
        let step = phase.transition(on: .modelStateChanged(.ready))
        #expect(step == SessionTransition(.startingCapture, [.startPipeline]))
    }

    @Test("the transcriber finding the model missing returns to waiting and stops capture")
    func modelMissingWhileListening() {
        let step = SessionPhase.listening(.hearing).transition(on: .modelStateChanged(.notInstalled))
        #expect(step == SessionTransition(.waitingForModel(.notInstalled), [.stopPipeline]))
        // The pipeline end that follows changes nothing.
        #expect(step.phase.applying(.pipelineEnded(failure: "not ready")) == step.phase)
    }

    @Test("Stop before capture started ends the session without stopping a pipeline")
    func stopBeforeCapture() {
        #expect(SessionPhase.checkingModel.transition(on: .stopRequested) == SessionTransition(.idle))
        let waiting = SessionPhase.waitingForModel(.downloading(fractionCompleted: 0.1))
        #expect(waiting.transition(on: .stopRequested) == SessionTransition(.idle))
        // A late model result after Stop does not start capture.
        #expect(SessionPhase.idle.transition(on: .modelStateChanged(.ready)) == SessionTransition(.idle))
    }

    @Test("an unexpected end of the pipeline is an error, not idle")
    func unexpectedEnd() {
        let step = SessionPhase.listening(.hearing).transition(on: .pipelineEnded(failure: nil))
        #expect(step.phase == .failed(message: SessionPhase.unexpectedEndMessage))
        let failure = SessionPhase.startingCapture.applying(.pipelineEnded(failure: "Model failed"))
        #expect(failure == .failed(message: "Model failed"))
    }

    @Test("Start retries after a failure or a denied permission")
    func restart() {
        for phase in [SessionPhase.failed(message: "x"), .permissionDenied(.system), .idle] {
            #expect(phase.transition(on: .startRequested) == SessionTransition(.checkingModel, [.checkModel]))
        }
    }

    @Test(
        "events that make no sense in a phase are ignored",
        arguments: [
            (SessionPhase.idle, SessionEvent.stopRequested),
            (.idle, .captureStatusChanged(.capturing)),
            (.idle, .pipelineEnded(failure: nil)),
            (.checkingModel, .startRequested),
            (.checkingModel, .captureStatusChanged(.capturing)),
            (.listening(.hearing), .startRequested),
            (.listening(.hearing), .modelStateChanged(.ready)),
            (.stopping, .startRequested),
            (.stopping, .stopRequested),
            (.stopping, .captureStatusChanged(.capturing)),
            (.stopping, .modelStateChanged(.ready)),
            (.waitingForModel(.downloading(fractionCompleted: nil)), .startRequested),
            (.failed(message: "x"), .stopRequested),
            (.failed(message: "x"), .pipelineEnded(failure: "y")),
            (.permissionDenied(.system), .pipelineEnded(failure: nil)),
            (.permissionDenied(.system), .captureStatusChanged(.capturing)),
        ]
    )
    func ignoredEvents(phase: SessionPhase, event: SessionEvent) {
        #expect(phase.transition(on: event) == SessionTransition(phase))
    }

    @Test(
        "Start and Stop enablement",
        arguments: [
            (SessionPhase.idle, true, false),
            (.checkingModel, false, true),
            (.waitingForModel(.notInstalled), true, true),
            (.waitingForModel(.downloading(fractionCompleted: nil)), false, true),
            (.startingCapture, false, true),
            (.listening(.noAudio), false, true),
            (.stopping, false, false),
            (.permissionDenied(.system), true, false),
            (.failed(message: "x"), true, false),
        ]
    )
    func enablement(phase: SessionPhase, canStart: Bool, canStop: Bool) {
        #expect(phase.canStart == canStart)
        #expect(phase.canStop == canStop)
    }

    @Test(
        "only a session with capture running or starting counts as capturing",
        arguments: [
            (SessionPhase.idle, false, false),
            (.checkingModel, false, true),
            (.waitingForModel(.notInstalled), false, true),
            (.startingCapture, true, true),
            (.listening(.hearing), true, true),
            (.stopping, false, true),
            (.permissionDenied(.system), false, false),
            (.failed(message: "x"), false, false),
        ]
    )
    func capturingAndActive(phase: SessionPhase, isCapturing: Bool, isActive: Bool) {
        #expect(phase.isCapturing == isCapturing)
        #expect(phase.isActive == isActive)
    }
}
