import Foundation

/// Re-reads the speech model state while macOS downloads the model and no
/// `install` call in this process reports progress (docs/DECISIONS.md 0021).
///
/// A download keeps running in the system when the app relaunches (the
/// welcome window asks for a relaunch after the permission grant) or when
/// `install` returns while the system still retries in the background. Then
/// nothing in this process would ever report `.ready`, and a session waiting
/// for the model would wait forever. The watch only reads the local asset
/// status (`SpeechAssetProvider.currentState()`); it never downloads.
public enum ModelStateWatch {
    /// Pause before the first re-read.
    public static let initialDelay: Duration = .seconds(2)
    /// The pause grows by one second per read up to this.
    public static let maximumDelay: Duration = .seconds(5)

    /// Whether the app should keep re-reading the model state.
    ///
    /// - Parameters:
    ///   - model: the last known model state.
    ///   - isInstalling: an `install` call in this process is running; it
    ///     reports progress itself.
    ///   - phase: the caption session.
    ///   - isWelcomeWindowOpen: the welcome window shows the model state.
    /// - Returns: true only while the model downloads, nothing in this process
    ///   reports on it, and someone waits for it (a session or the welcome
    ///   window).
    public static func shouldWatch(
        model: SpeechAssetState,
        isInstalling: Bool,
        phase: SessionPhase,
        isWelcomeWindowOpen: Bool
    ) -> Bool {
        guard case .downloading = model, !isInstalling else { return false }
        return isWaitingForModel(phase) || isWelcomeWindowOpen
    }

    /// Pause before re-read number `attempt` (0 for the first): 2 s, 3 s,
    /// 4 s, then 5 s.
    public static func delay(beforeAttempt attempt: Int) -> Duration {
        let step = Duration.seconds(max(attempt, 0))
        return min(initialDelay + step, maximumDelay)
    }

    /// Re-reads the state until it is no longer downloading, `onState`
    /// returns false, or the task is cancelled.
    ///
    /// - Parameters:
    ///   - assets: where the state is read; never asked to install.
    ///   - sleep: waits between reads (a test passes one that does not wait).
    ///   - onState: gets each state read; returns whether to go on (the app
    ///     checks `shouldWatch` again there).
    public static func run(
        assets: any SpeechAssetProvider,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onState: @Sendable (SpeechAssetState) async -> Bool
    ) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try await sleep(delay(beforeAttempt: attempt))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let state = await assets.currentState()
            guard !Task.isCancelled else { return }
            attempt += 1
            let goOn = await onState(state)
            guard goOn, case .downloading = state else { return }
        }
    }

    private static func isWaitingForModel(_ phase: SessionPhase) -> Bool {
        switch phase {
        case .checkingModel, .waitingForModel: true
        case .idle, .startingCapture, .listening, .stopping, .permissionDenied, .failed: false
        }
    }
}
