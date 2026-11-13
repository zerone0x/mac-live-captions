import Foundation
import Testing
@testable import LiveCaptionsCore

@Suite("AudioCaptureStatus")
struct AudioCaptureStatusTests {
    @Test("happy path: start, capture, silence, sound, stop")
    func happyPath() {
        var status = AudioCaptureStatus.idle
        status = status.applying(.startRequested)
        #expect(status == .starting)
        status = status.applying(.started)
        #expect(status == .capturing)
        status = status.applying(.silenceDetected)
        #expect(status == .noAudio)
        #expect(status.statusText == "No audio playing")
        status = status.applying(.soundDetected)
        #expect(status == .capturing)
        status = status.applying(.stopped)
        #expect(status == .idle)
    }

    @Test("denied permission is an explicit error that tells the user what to do")
    func permissionDenied() {
        let status = AudioCaptureStatus.starting.applying(.permissionDenied(.system))
        #expect(status == .permissionDenied(.system))
        #expect(status.isError)
        #expect(!status.isActive)
        #expect(status.statusText.contains("System Settings"))
        #expect(status.statusText.contains("reopen"))
        // The user can try again (for example after relaunching).
        #expect(status.applying(.startRequested) == .starting)
    }

    @Test("an interruption reconnects, then capture resumes")
    func reconnect() {
        var status = AudioCaptureStatus.capturing.applying(.interrupted(attempt: 1))
        #expect(status == .reconnecting(attempt: 1))
        #expect(status.isActive)
        status = status.applying(.interrupted(attempt: 2))
        #expect(status == .reconnecting(attempt: 2))
        status = status.applying(.started)
        #expect(status == .capturing)
    }

    @Test(
        "a stream that dies while capturing shows 'reconnecting', even when nothing was playing",
        arguments: [AudioCaptureStatus.starting, .capturing, .noAudio, .reconnecting(attempt: 1)]
    )
    func interruptionFromEveryActiveStatus(status: AudioCaptureStatus) {
        #expect(status.applying(.interrupted(attempt: 2)) == .reconnecting(attempt: 2))
    }

    @Test("a restarted stream clears 'No audio' (its silence monitor starts afresh)")
    func startedClearsNoAudio() {
        #expect(AudioCaptureStatus.noAudio.applying(.started) == .capturing)
    }

    @Test("giving up after reconnecting is a failure")
    func reconnectFails() {
        let status = AudioCaptureStatus.reconnecting(attempt: 6).applying(.failed("stream stopped"))
        #expect(status == .failed(message: "stream stopped"))
        #expect(status.isError)
        #expect(status.statusText == "Audio capture failed: stream stopped")
    }

    @Test("stop always returns to idle", arguments: [
        AudioCaptureStatus.idle, .starting, .capturing, .noAudio,
        .reconnecting(attempt: 3), .permissionDenied(.microphone), .failed(message: "x"),
    ])
    func stopFromAnywhere(status: AudioCaptureStatus) {
        #expect(status.applying(.stopped) == .idle)
    }

    @Test("events that make no sense in a status are ignored", arguments: [
        (AudioCaptureStatus.idle, AudioCaptureEvent.started),
        (.idle, .silenceDetected),
        (.idle, .interrupted(attempt: 1)),
        (.idle, .failed("x")),
        (.idle, .permissionDenied(.system)),
        (.starting, .silenceDetected),
        (.capturing, .startRequested),
        (.capturing, .soundDetected),
        (.capturing, .started),
        (.noAudio, .silenceDetected),
        (.reconnecting(attempt: 1), .silenceDetected),
        (.failed(message: "x"), .started),
        (.permissionDenied(.system), .started),
        (.permissionDenied(.system), .failed("y")),
    ])
    func ignoredEvents(status: AudioCaptureStatus, event: AudioCaptureEvent) {
        #expect(status.applying(event) == status)
    }

    @Test("errors map to the matching status event")
    func errorEvents() {
        #expect(AudioCaptureError.permissionDenied(.microphone).event == .permissionDenied(.microphone))
        #expect(AudioCaptureError.unavailable("no display").event == .failed("no display"))
        #expect(AudioCaptureError.interrupted("gone").event == .failed("gone"))
        #expect(AudioCaptureError.permissionDenied(.microphone).localizedDescription.contains("Microphone"))
        #expect(AudioCaptureError.unavailable("No display found.").localizedDescription == "No display found.")
    }
}
