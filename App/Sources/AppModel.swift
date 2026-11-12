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
}
