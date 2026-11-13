import Testing

@testable import LiveCaptionsCore

@Suite("SessionStatus (menu bar)")
struct SessionStatusTests {
    typealias Indicator = SessionStatus.Indicator

    /// The menu-bar table: phase (with the model ready and no capture test)
    /// → status line and icon.
    @Test(
        "each session phase has an honest status line and icon",
        arguments: [
            (SessionPhase.idle, "Not listening", Indicator.off),
            (.checkingModel, "Checking English speech model…", .busy),
            (.waitingForModel(.notInstalled), "Waiting for the English speech model", .attention),
            (.waitingForModel(.downloading(fractionCompleted: 0.42)), "Downloading English speech model (42%)…", .busy),
            (
                .waitingForModel(.unsupported), "On-device English speech recognition is not supported on this Mac",
                .attention
            ),
            (.waitingForModel(.failed(message: "offline")), "Speech model error: offline", .attention),
            (.startingCapture, "Starting audio capture…", .busy),
            (.listening(.hearing), "Listening", .listening),
            (.listening(.noAudio), "Listening, no audio playing", .listening),
            (.listening(.reconnecting(attempt: 3)), "Audio interrupted, reconnecting (attempt 3)…", .listening),
            (.stopping, "Stopping…", .busy),
            (.permissionDenied(.system), "Waiting for permission", .attention),
            (.failed(message: "Audio capture failed"), "Error: Audio capture failed", .attention),
        ]
    )
    func table(phase: SessionPhase, text: String, indicator: Indicator) {
        let status = SessionStatus(phase: phase, model: .ready)
        #expect(status.text == text)
        #expect(status.indicator == indicator)
    }

    @Test("only phases with capture running show as listening, not while it starts")
    func listeningMatchesCapture() {
        let phases: [SessionPhase] = [
            .idle, .checkingModel, .waitingForModel(.notInstalled), .startingCapture,
            .listening(.hearing), .listening(.noAudio), .stopping, .permissionDenied(.system),
            .failed(message: "x"),
        ]
        for phase in phases {
            let status = SessionStatus(phase: phase, model: .ready)
            #expect(status.isListening == phase.isCapturing, "\(phase)")
        }
    }

    @Test("a running capture test shows as listening even without a session")
    func captureTestIsListening() {
        for test in [AudioCaptureStatus.starting, .capturing, .noAudio, .reconnecting(attempt: 1)] {
            let status = SessionStatus(phase: .idle, model: .ready, captureTest: test)
            #expect(status.isListening)
            #expect(status.text == "Listening (audio capture test)")
        }
        let stopped = SessionStatus(phase: .idle, model: .ready, captureTest: .permissionDenied(.system))
        #expect(!stopped.isListening)
        #expect(stopped.text == "Not listening")
    }

    @Test("the permission state explains what to do and offers help")
    func permissionHelp() {
        let status = SessionStatus(phase: .permissionDenied(.system), model: .ready)
        let detail = status.detail ?? ""
        #expect(detail.contains("Screen & System Audio Recording"))
        #expect(status.offersPermissionHelp)
        #expect(!status.offersModelDownload)
    }

    @Test("a missing model offers the download, while idle and while waiting")
    func modelDownloadOffer() {
        let waiting = SessionStatus(phase: .waitingForModel(.notInstalled), model: .notInstalled)
        #expect(waiting.offersModelDownload)
        let idle = SessionStatus(phase: .idle, model: .notInstalled)
        #expect(idle.offersModelDownload)
        #expect(idle.indicator == .off)
        let ready = SessionStatus(phase: .idle, model: .ready)
        #expect(!ready.offersModelDownload)
        let downloading = SessionStatus(phase: .waitingForModel(.downloading(fractionCompleted: nil)), model: .ready)
        #expect(!downloading.offersModelDownload)
    }

    @Test("a failed download offers the download again while idle")
    func idleFailedDownload() {
        let status = SessionStatus(phase: .idle, model: .failed(message: "offline"))
        #expect(status.offersModelDownload)
        #expect(status.text == "Not listening")
        #expect(status.detail == "Speech model error: offline")
        #expect(status.indicator == .off)
        let waiting = SessionStatus(
            phase: .waitingForModel(.failed(message: "offline")), model: .failed(message: "offline"))
        #expect(waiting.offersModelDownload)
    }

    @Test("a download started from onboarding shows while idle")
    func idleDownload() {
        let status = SessionStatus(phase: .idle, model: .downloading(fractionCompleted: 0.1))
        #expect(status.text == "Downloading English speech model (10%)…")
        #expect(status.indicator == .busy)
        #expect(!status.isListening)
    }
}
