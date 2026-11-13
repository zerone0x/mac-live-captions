import Foundation

/// What the menu bar shows: one status line, the icon, and which actions make
/// sense. Derived from the session phase, the speech model state and the
/// debug capture test, so the menu never claims more than really runs
/// (docs/DECISIONS.md, 0014).
public struct SessionStatus: Sendable, Hashable {
    /// Icon kind; the app maps it to an SF Symbol.
    public enum Indicator: Sendable, Hashable {
        /// Nothing is captured.
        case off
        /// Something is working towards captions (checking, downloading,
        /// starting, stopping); nothing is captured yet.
        case busy
        /// Audio is being captured right now.
        case listening
        /// The user has to act (permission, model, error).
        case attention
    }

    /// One short line for the menu.
    public var text: String
    /// Optional second line: what to do next.
    public var detail: String?
    public var indicator: Indicator
    /// Offer "Download English Speech Model".
    public var offersModelDownload: Bool
    /// Offer "Open Privacy Settings…" and "Relaunch".
    public var offersPermissionHelp: Bool

    public init(
        text: String,
        detail: String? = nil,
        indicator: Indicator,
        offersModelDownload: Bool = false,
        offersPermissionHelp: Bool = false
    ) {
        self.text = text
        self.detail = detail
        self.indicator = indicator
        self.offersModelDownload = offersModelDownload
        self.offersPermissionHelp = offersPermissionHelp
    }

    /// Any capture in progress, the debug capture test included, shows as
    /// listening.
    public var isListening: Bool { indicator == .listening }

    /// Builds the status.
    ///
    /// - Parameters:
    ///   - phase: the caption session.
    ///   - model: the en-US speech model, tracked even without a session
    ///     (for example while it downloads from onboarding).
    ///   - captureTest: status of the "Debug: Audio Capture" probe.
    public init(phase: SessionPhase, model: SpeechAssetState, captureTest: AudioCaptureStatus = .idle) {
        switch phase {
        case .idle:
            self = Self.idleStatus(model: model, captureTest: captureTest)
        case .checkingModel:
            self.init(text: SpeechAssetState.checking.statusText, indicator: .busy)
        case .waitingForModel(let state):
            self = Self.waiting(for: state)
        case .startingCapture:
            self.init(text: "Starting audio capture…", indicator: .listening)
        case .listening(.hearing):
            self.init(text: "Listening", indicator: .listening)
        case .listening(.noAudio):
            self.init(
                text: "Listening, no audio playing",
                detail: "Captions appear when your Mac plays speech.",
                indicator: .listening
            )
        case .listening(.reconnecting(let attempt)):
            self.init(
                text: AudioCaptureStatus.reconnecting(attempt: attempt).statusText,
                indicator: .listening
            )
        case .stopping:
            self.init(text: "Stopping…", indicator: .busy)
        case .permissionDenied(let origin):
            self.init(
                text: "Waiting for permission",
                detail: AudioCaptureError.permissionDenied(origin).localizedDescription,
                indicator: .attention,
                offersPermissionHelp: true
            )
        case .failed(let message):
            self.init(text: "Error: \(message)", indicator: .attention)
        }
    }

    // MARK: - Private

    private static func idleStatus(model: SpeechAssetState, captureTest: AudioCaptureStatus) -> SessionStatus {
        if captureTest.isActive {
            return SessionStatus(
                text: "Listening (audio capture test)",
                detail: "Stop the test in Debug: Audio Capture.",
                indicator: .listening
            )
        }
        switch model {
        case .downloading:
            return SessionStatus(text: model.statusText, indicator: .busy)
        case .notInstalled:
            return SessionStatus(
                text: "Not listening",
                detail: "The English speech model is not installed yet.",
                indicator: .off,
                offersModelDownload: true
            )
        default:
            return SessionStatus(text: "Not listening", indicator: .off)
        }
    }

    private static func waiting(for state: SpeechAssetState) -> SessionStatus {
        switch state {
        case .downloading:
            return SessionStatus(
                text: state.statusText,
                detail: "Captions start when the download finishes.",
                indicator: .busy
            )
        case .notInstalled:
            return SessionStatus(
                text: "Waiting for the English speech model",
                detail: "Download it to start captions. macOS downloads it once from Apple.",
                indicator: .attention,
                offersModelDownload: true
            )
        case .failed:
            return SessionStatus(text: state.statusText, indicator: .attention, offersModelDownload: true)
        case .checking, .ready, .unsupported:
            return SessionStatus(text: state.statusText, indicator: .attention)
        }
    }
}
