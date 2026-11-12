import Foundation
import LiveCaptionsCore
import Observation

/// App-level state. Thin glue: the transitions live in `SessionPhase` (Core).
///
/// Start/Stop are placeholders until the audio source (#7) and transcriber (#8)
/// are wired in (#11): they only move the phase so the menu can be exercised.
@MainActor
@Observable
final class AppModel {
    private(set) var phase: SessionPhase = .idle

    /// Debug-only audio capture check (#7), independent of `phase`.
    let captureProbe = AudioCaptureProbe()

    /// The notch overlay. Real captions reach it through `CaptionPresenter`
    /// once the pipeline is wired (#11); until then only the demo feeds it.
    let overlay = NotchOverlayController()

    private(set) var isDemoPlaying = false
    @ObservationIgnored private var demoTask: Task<Void, Never>?

    /// Best effort, see `NotchOverlayController.hidesFromScreenSharing`.
    var hideOverlayFromScreenSharing: Bool {
        didSet {
            UserDefaults.standard.set(hideOverlayFromScreenSharing, forKey: Self.hideFromSharingKey)
            overlay.hidesFromScreenSharing = hideOverlayFromScreenSharing
        }
    }

    private static let hideFromSharingKey = "hideOverlayFromScreenSharing"

    init() {
        let hide = UserDefaults.standard.bool(forKey: Self.hideFromSharingKey)
        hideOverlayFromScreenSharing = hide
        overlay.hidesFromScreenSharing = hide
    }

    func start() {
        send(.startRequested)
        send(.didStart)
    }

    func stop() {
        send(.stopRequested)
        send(.didStop)
    }

    private func send(_ event: SessionEvent) {
        phase = phase.applying(event)
    }

    // MARK: Demo captions

    func toggleDemo() {
        if isDemoPlaying {
            stopDemo()
        } else {
            playDemo()
        }
    }

    /// Plays the scripted English feed into the overlay, so it can be seen
    /// without audio or permissions.
    func playDemo(_ script: CaptionDemoScript = .english) {
        demoTask?.cancel()
        overlay.present(.empty)
        isDemoPlaying = true
        demoTask = Task { [weak self] in
            for step in script.steps {
                try? await Task.sleep(for: .seconds(step.delay))
                guard !Task.isCancelled else { return }
                self?.overlay.present(step.snapshot)
            }
            // Leave the last caption up; the overlay collapses when idle.
            self?.isDemoPlaying = false
            self?.demoTask = nil
        }
    }

    func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        isDemoPlaying = false
        overlay.present(.empty)
    }
}
