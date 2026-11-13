import Foundation

/// How a running capture session is doing.
public enum ListeningHealth: Sendable, Hashable {
    /// Audio with sound in it is arriving.
    case hearing
    /// Capture runs, but only silence arrives: nothing is playing.
    case noAudio
    /// The stream stopped unexpectedly and the source is reconnecting.
    case reconnecting(attempt: Int)
}

/// Lifecycle of a caption session (system audio → speech → overlay).
///
/// Pure state machine (docs/DECISIONS.md, 0014): the app sends `SessionEvent`s
/// and performs the `SessionEffect`s each transition asks for. The phase only
/// says "listening" after the audio source has reported that capture started,
/// never because Start was clicked.
public enum SessionPhase: Sendable, Hashable {
    /// No session.
    case idle
    /// Start was requested; checking the en-US speech model.
    case checkingModel
    /// The speech model is not ready (not installed, downloading, unsupported
    /// or failed). The session starts by itself once the model reports ready.
    case waitingForModel(SpeechAssetState)
    /// The model is ready and the audio source is starting.
    case startingCapture
    /// The audio source reported that capture runs.
    case listening(ListeningHealth)
    /// Stop was requested; waiting for the pipeline to finish.
    case stopping
    /// The user has not allowed audio capture. Start tries again.
    case permissionDenied(AudioOrigin)
    /// The session ended with an error. Start tries again.
    case failed(message: String)

    /// Whether "Start" should be enabled.
    public var canStart: Bool {
        switch self {
        case .idle, .permissionDenied, .failed: true
        case .waitingForModel(let state): !Self.isDownloading(state)
        case .checkingModel, .startingCapture, .listening, .stopping: false
        }
    }

    /// Whether "Stop" should be enabled.
    public var canStop: Bool {
        switch self {
        case .checkingModel, .waitingForModel, .startingCapture, .listening: true
        case .idle, .stopping, .permissionDenied, .failed: false
        }
    }

    /// Whether the session holds (or is acquiring) the audio source.
    public var isCapturing: Bool {
        switch self {
        case .startingCapture, .listening: true
        default: false
        }
    }

    /// Whether a session was requested and has not ended yet. While active,
    /// the demo feed and the capture test stay off.
    public var isActive: Bool {
        switch self {
        case .checkingModel, .waitingForModel, .startingCapture, .listening, .stopping: true
        case .idle, .permissionDenied, .failed: false
        }
    }

    /// Returns the phase after `event`, ignoring the effects.
    public func applying(_ event: SessionEvent) -> SessionPhase {
        transition(on: event).phase
    }

    /// Returns the phase after `event` and the work the app must do for it.
    /// Events that make no sense in the current phase are ignored: the phase
    /// is returned unchanged with no effects.
    public func transition(on event: SessionEvent) -> SessionTransition {
        switch event {
        case .startRequested:
            guard canStart else { return unchanged }
            return SessionTransition(.checkingModel, [.checkModel])

        case .stopRequested:
            switch self {
            case .checkingModel, .waitingForModel:
                // Nothing runs yet. A system download keeps going on its own.
                return SessionTransition(.idle)
            case .startingCapture, .listening:
                return SessionTransition(.stopping, [.stopPipeline])
            default:
                return unchanged
            }

        case .modelStateChanged(let state):
            return modelChanged(to: state)

        case .captureStatusChanged(let status):
            return captureChanged(to: status)

        case .pipelineEnded(let failure):
            switch self {
            case .stopping:
                return SessionTransition(.idle)
            case .startingCapture, .listening:
                let message = failure ?? Self.unexpectedEndMessage
                return SessionTransition(.failed(message: message), [.stopPipeline])
            default:
                // Already reported (permission, model, failure) or not running.
                return unchanged
            }
        }
    }

    static let unexpectedEndMessage = "Captions stopped unexpectedly"

    // MARK: - Private

    private var unchanged: SessionTransition { SessionTransition(self) }

    private func modelChanged(to state: SpeechAssetState) -> SessionTransition {
        switch self {
        case .checkingModel, .waitingForModel:
            switch state {
            case .ready:
                return SessionTransition(.startingCapture, [.startPipeline])
            case .checking:
                return unchanged
            default:
                return SessionTransition(.waitingForModel(state))
            }
        case .startingCapture, .listening:
            // The transcriber found the model missing after all.
            switch state {
            case .ready, .checking:
                return unchanged
            default:
                return SessionTransition(.waitingForModel(state), [.stopPipeline])
            }
        default:
            return unchanged
        }
    }

    private func captureChanged(to status: AudioCaptureStatus) -> SessionTransition {
        switch self {
        case .startingCapture, .listening:
            switch status {
            case .capturing:
                return SessionTransition(.listening(.hearing))
            case .noAudio:
                return SessionTransition(.listening(.noAudio))
            case .reconnecting(let attempt):
                return SessionTransition(.listening(.reconnecting(attempt: attempt)))
            case .permissionDenied(let origin):
                return SessionTransition(.permissionDenied(origin), [.stopPipeline])
            case .failed(let message):
                return SessionTransition(.failed(message: message), [.stopPipeline])
            case .idle, .starting:
                // `.idle` comes with the end of the stream; `pipelineEnded`
                // decides what that means.
                return unchanged
            }
        case .failed:
            // A more specific reason than the error that ended the stream.
            if case .permissionDenied(let origin) = status {
                return SessionTransition(.permissionDenied(origin))
            }
            return unchanged
        default:
            return unchanged
        }
    }

    private static func isDownloading(_ state: SpeechAssetState) -> Bool {
        if case .downloading = state { true } else { false }
    }
}

/// Inputs to `SessionPhase`.
public enum SessionEvent: Sendable, Hashable {
    /// The user asked to start captions (menu, hotkey or onboarding).
    case startRequested
    /// The user asked to stop captions.
    case stopRequested
    /// The speech model was checked, or its download progressed.
    case modelStateChanged(SpeechAssetState)
    /// The audio source of the current session reported a new status.
    case captureStatusChanged(AudioCaptureStatus)
    /// The pipeline of the current session finished; `failure` says why when
    /// it ended with an error.
    case pipelineEnded(failure: String?)
}

/// Work the app performs after a transition.
public enum SessionEffect: Sendable, Hashable {
    /// Read the speech model state (no download) and report it with
    /// `modelStateChanged`.
    case checkModel
    /// Start the audio source and the transcriber. Report source status with
    /// `captureStatusChanged` and the end with `pipelineEnded`.
    case startPipeline
    /// Stop the audio source; the pipeline then ends with `pipelineEnded`.
    case stopPipeline
}

/// A new phase plus the effects to perform, in order.
public struct SessionTransition: Sendable, Hashable {
    public var phase: SessionPhase
    public var effects: [SessionEffect]

    public init(_ phase: SessionPhase, _ effects: [SessionEffect] = []) {
        self.phase = phase
        self.effects = effects
    }
}
