import Foundation

/// Health of an audio source while it captures, as shown to the user.
///
/// This is a pure state machine, like `SessionPhase`: a capture adapter sends
/// `AudioCaptureEvent`s and renders the status. Every problem the user can fix
/// (permission, nothing playing) is an explicit state, never a silent failure.
public enum AudioCaptureStatus: Sendable, Hashable {
    /// Not capturing.
    case idle
    /// Asked to start; waiting for permission and the first stream.
    case starting
    /// Audio is arriving and is not silent.
    case capturing
    /// Capture runs, but only silence has arrived for a while: nothing is
    /// playing, or the playing app is muted.
    case noAudio
    /// The stream stopped unexpectedly (for example after an output device
    /// change) and the source is reconnecting. `attempt` starts at 1.
    case reconnecting(attempt: Int)
    /// The user has not allowed capture. For system audio the app must be
    /// relaunched after the permission is granted.
    case permissionDenied(AudioOrigin)
    /// Capture stopped and will not recover without a new start.
    case failed(message: String)

    /// Whether the source holds (or is acquiring) the capture device.
    public var isActive: Bool {
        switch self {
        case .starting, .capturing, .noAudio, .reconnecting: true
        case .idle, .permissionDenied, .failed: false
        }
    }

    /// Whether this status is a terminal problem the user has to act on.
    public var isError: Bool {
        switch self {
        case .permissionDenied, .failed: true
        default: false
        }
    }

    /// Short status text for the menu.
    public var statusText: String {
        switch self {
        case .idle: "Not capturing"
        case .starting: "Starting audio capture…"
        case .capturing: "Capturing audio"
        case .noAudio: "No audio playing"
        case .reconnecting(let attempt): "Audio interrupted, reconnecting (attempt \(attempt))…"
        case .permissionDenied(let origin): AudioCaptureError.permissionDenied(origin).localizedDescription
        case .failed(let message): "Audio capture failed: \(message)"
        }
    }

    /// Returns the status after `event`. Events that make no sense in the
    /// current status are ignored and the status is returned unchanged.
    public func applying(_ event: AudioCaptureEvent) -> AudioCaptureStatus {
        switch (self, event) {
        case (_, .stopped):
            .idle
        case (.idle, .startRequested), (.failed, .startRequested), (.permissionDenied, .startRequested):
            .starting
        // `.started` from `.noAudio`: a stream that was rebuilt (device-change
        // restart, reconnect) starts its silence monitor afresh, so "no audio"
        // must clear too; otherwise sound on the new stream is never reported
        // and the menu stays on "No audio playing". If it stays quiet, the
        // monitor reports silence again after its timeout.
        case (.starting, .started), (.reconnecting, .started), (.noAudio, .started):
            .capturing
        case (.capturing, .silenceDetected):
            .noAudio
        case (.noAudio, .soundDetected):
            .capturing
        case (.starting, .interrupted(let attempt)),
            (.capturing, .interrupted(let attempt)),
            (.noAudio, .interrupted(let attempt)),
            (.reconnecting, .interrupted(let attempt)):
            .reconnecting(attempt: attempt)
        case (.starting, .permissionDenied(let origin)),
            (.capturing, .permissionDenied(let origin)),
            (.noAudio, .permissionDenied(let origin)),
            (.reconnecting, .permissionDenied(let origin)):
            .permissionDenied(origin)
        case (.starting, .failed(let message)),
            (.capturing, .failed(let message)),
            (.noAudio, .failed(let message)),
            (.reconnecting, .failed(let message)):
            .failed(message: message)
        default:
            self
        }
    }
}

/// Inputs to `AudioCaptureStatus`.
public enum AudioCaptureEvent: Sendable, Hashable {
    case startRequested
    case started
    case silenceDetected
    case soundDetected
    /// The stream stopped unexpectedly; reconnect attempt number `attempt`.
    case interrupted(attempt: Int)
    case permissionDenied(AudioOrigin)
    case failed(String)
    case stopped
}

/// Errors thrown by audio sources, from `start()` or through the chunk stream.
public enum AudioCaptureError: Error, Sendable, Hashable, LocalizedError {
    /// The user has not granted the capture permission for `origin`.
    case permissionDenied(AudioOrigin)
    /// Capture cannot start on this Mac right now (no display, no input device,
    /// unsupported format). The message says why.
    case unavailable(String)
    /// The stream stopped and reconnecting gave up.
    case interrupted(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(.system):
            "Screen & System Audio Recording is off for LiveCaptions. Turn it on in System Settings > Privacy & Security, then quit and reopen LiveCaptions."
        case .permissionDenied(.microphone):
            "Microphone access is off for LiveCaptions. Turn it on in System Settings > Privacy & Security > Microphone."
        case .unavailable(let reason):
            reason
        case .interrupted(let reason):
            "Audio capture stopped: \(reason)"
        }
    }

    /// The `AudioCaptureEvent` that reports this error to the status machine.
    public var event: AudioCaptureEvent {
        switch self {
        case .permissionDenied(let origin): .permissionDenied(origin)
        case .unavailable(let reason), .interrupted(let reason): .failed(reason)
        }
    }
}
