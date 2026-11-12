import Foundation

/// Lifecycle of a capture session, as shown in the menu bar.
///
/// This is a pure state machine: the app sends events and renders the phase.
/// Permission states are added when the real audio source lands.
public enum SessionPhase: Sendable, Hashable {
    case idle
    case starting
    case running
    case stopping
    case failed(message: String)

    /// Whether "Start" should be enabled.
    public var canStart: Bool {
        switch self {
        case .idle, .failed: true
        case .starting, .running, .stopping: false
        }
    }

    /// Whether "Stop" should be enabled.
    public var canStop: Bool {
        switch self {
        case .starting, .running: true
        case .idle, .stopping, .failed: false
        }
    }

    /// Short status text for the menu.
    public var statusText: String {
        switch self {
        case .idle: "Not listening"
        case .starting: "Starting…"
        case .running: "Listening"
        case .stopping: "Stopping…"
        case .failed(let message): "Error: \(message)"
        }
    }

    /// Returns the phase after `event`. Events that make no sense in the
    /// current phase are ignored and the phase is returned unchanged.
    public func applying(_ event: SessionEvent) -> SessionPhase {
        switch (self, event) {
        case (.idle, .startRequested), (.failed, .startRequested):
            .starting
        case (.starting, .didStart):
            .running
        case (.starting, .stopRequested), (.running, .stopRequested):
            .stopping
        case (.stopping, .didStop), (.running, .didStop):
            .idle
        case (.starting, .didFail(let message)),
             (.running, .didFail(let message)),
             (.stopping, .didFail(let message)):
            .failed(message: message)
        default:
            self
        }
    }
}

/// Inputs to `SessionPhase`.
public enum SessionEvent: Sendable, Hashable {
    case startRequested
    case didStart
    case stopRequested
    case didStop
    case didFail(String)
}
