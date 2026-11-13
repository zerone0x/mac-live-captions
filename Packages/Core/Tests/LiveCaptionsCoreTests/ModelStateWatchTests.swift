import Foundation
import Testing

@testable import LiveCaptionsCore

@Suite("ModelStateWatch (download this process does not drive, #40)")
struct ModelStateWatchTests {
    @Test("a download nobody in this process reports on is watched while a session waits")
    func watchesForWaitingSession() {
        for phase in [SessionPhase.checkingModel, .waitingForModel(.downloading(fractionCompleted: nil))] {
            #expect(
                ModelStateWatch.shouldWatch(
                    model: .downloading(fractionCompleted: nil), isInstalling: false, phase: phase,
                    isWelcomeWindowOpen: false
                ),
                "\(phase)"
            )
        }
        #expect(
            ModelStateWatch.shouldWatch(
                model: .downloading(fractionCompleted: 0.42), isInstalling: false,
                phase: .waitingForModel(.downloading(fractionCompleted: 0.42)), isWelcomeWindowOpen: false
            )
        )
    }

    @Test("the welcome window showing the download is watched without a session")
    func watchesForWelcomeWindow() {
        #expect(
            ModelStateWatch.shouldWatch(
                model: .downloading(fractionCompleted: nil), isInstalling: false, phase: .idle,
                isWelcomeWindowOpen: true
            )
        )
        #expect(
            !ModelStateWatch.shouldWatch(
                model: .downloading(fractionCompleted: nil), isInstalling: false, phase: .idle,
                isWelcomeWindowOpen: false
            )
        )
    }

    @Test("an install in this process reports progress itself: no watch")
    func noWatchWhileInstalling() {
        #expect(
            !ModelStateWatch.shouldWatch(
                model: .downloading(fractionCompleted: 0.1), isInstalling: true,
                phase: .waitingForModel(.downloading(fractionCompleted: 0.1)), isWelcomeWindowOpen: true
            )
        )
    }

    @Test(
        "states other than downloading are not watched",
        arguments: [
            SpeechAssetState.checking, .notInstalled, .ready, .unsupported, .failed(message: "offline"),
        ]
    )
    func noWatchWhenNotDownloading(model: SpeechAssetState) {
        #expect(
            !ModelStateWatch.shouldWatch(
                model: model, isInstalling: false, phase: .waitingForModel(model), isWelcomeWindowOpen: true
            )
        )
    }

    @Test(
        "phases that do not wait for the model stop the watch",
        arguments: [
            SessionPhase.idle, .startingCapture, .listening(.hearing), .stopping, .permissionDenied(.system),
            .failed(message: "x"),
        ]
    )
    func noWatchOutsideWaitingPhases(phase: SessionPhase) {
        #expect(
            !ModelStateWatch.shouldWatch(
                model: .downloading(fractionCompleted: nil), isInstalling: false, phase: phase,
                isWelcomeWindowOpen: false
            )
        )
    }

    @Test("the pause backs off from 2 s to at most 5 s")
    func backoff() {
        let delays = (-1...6).map { ModelStateWatch.delay(beforeAttempt: $0) }
        #expect(delays == [2, 2, 3, 4, 5, 5, 5, 5].map { Duration.seconds($0) })
    }

    @Test("re-reads until the model is ready and stops there, with backed-off pauses")
    func runUntilReady() async {
        let assets = SequencedSpeechAssets([
            .downloading(fractionCompleted: nil), .downloading(fractionCompleted: nil), .ready, .ready,
        ])
        let sleeps = DurationLog()
        let seen = StateLog()
        await ModelStateWatch.run(
            assets: assets, sleep: { sleeps.append($0) },
            onState: { state in
                seen.append(state)
                return true
            })
        #expect(seen.values == [.downloading(fractionCompleted: nil), .downloading(fractionCompleted: nil), .ready])
        #expect(sleeps.values == [.seconds(2), .seconds(3), .seconds(4)])
        #expect(await assets.installCalls == 0)
    }

    @Test("stops on a failed or missing model, which then offers Download again")
    func stopsOnFailureOrMissing() async {
        for end in [SpeechAssetState.failed(message: "offline"), .notInstalled] {
            let assets = SequencedSpeechAssets([.downloading(fractionCompleted: nil), end, .ready])
            let seen = StateLog()
            await ModelStateWatch.run(
                assets: assets, sleep: { _ in },
                onState: { state in
                    seen.append(state)
                    return true
                })
            #expect(seen.values == [.downloading(fractionCompleted: nil), end])
            #expect(SessionStatus(phase: .waitingForModel(end), model: end).offersModelDownload)
        }
    }

    @Test("stops when the app says the watch is no longer needed")
    func stopsWhenOnStateDeclines() async {
        let assets = SequencedSpeechAssets([.downloading(fractionCompleted: nil)])
        let seen = StateLog()
        await ModelStateWatch.run(
            assets: assets, sleep: { _ in },
            onState: { state in
                seen.append(state)
                return false
            })
        #expect(seen.values.count == 1)
    }

    @Test("a cancelled sleep (Stop, quit) ends the watch without another read")
    func stopsWhenSleepThrows() async {
        let assets = SequencedSpeechAssets([.downloading(fractionCompleted: nil)])
        await ModelStateWatch.run(
            assets: assets, sleep: { _ in throw CancellationError() },
            onState: { _ in
                Issue.record("no read after a cancelled sleep")
                return true
            })
        #expect(await assets.reads == 0)
    }

    @Test("a cancelled task ends the watch")
    func stopsWhenCancelled() async {
        let assets = SequencedSpeechAssets([.downloading(fractionCompleted: nil)])
        let task = Task {
            await ModelStateWatch.run(assets: assets, sleep: { try await Task.sleep(for: $0) }) { _ in true }
        }
        task.cancel()
        await task.value
        #expect(await assets.reads == 0)
    }

    /// The bug in #40: after a relaunch mid-download the session waits for
    /// `.downloading` and nothing in this process installs. The watch must
    /// bring the session to capture by itself once the model is ready.
    @Test("relaunch during a download: the waiting session starts once the model is ready")
    func relaunchDuringDownloadStartsCaptions() async {
        let assets = SequencedSpeechAssets([
            .downloading(fractionCompleted: nil), .downloading(fractionCompleted: nil), .ready,
        ])
        let session = SessionDriver()
        // Start in the new process: the one-time check says downloading.
        await session.send(.startRequested)
        await session.send(.modelStateChanged(.downloading(fractionCompleted: nil)))
        #expect(await session.phase == .waitingForModel(.downloading(fractionCompleted: nil)))
        #expect(await session.shouldWatch)

        await ModelStateWatch.run(
            assets: assets, sleep: { _ in },
            onState: { state in
                await session.send(.modelStateChanged(state))
                return await session.shouldWatch
            })

        #expect(await session.phase == .startingCapture)
        #expect(await session.effects.last == .startPipeline)
    }
}

/// Session phase plus model state, as the app keeps them.
private actor SessionDriver {
    private(set) var phase: SessionPhase = .idle
    private(set) var model: SpeechAssetState = .checking
    private(set) var effects: [SessionEffect] = []

    func send(_ event: SessionEvent) {
        if case .modelStateChanged(let state) = event {
            model = state
        }
        let transition = phase.transition(on: event)
        phase = transition.phase
        effects += transition.effects
    }

    var shouldWatch: Bool {
        ModelStateWatch.shouldWatch(model: model, isInstalling: false, phase: phase, isWelcomeWindowOpen: false)
    }
}

/// Returns the given states one read at a time, then repeats the last one.
private actor SequencedSpeechAssets: SpeechAssetProvider {
    private let states: [SpeechAssetState]
    private(set) var reads = 0
    private(set) var installCalls = 0

    init(_ states: [SpeechAssetState]) {
        self.states = states
    }

    func currentState() -> SpeechAssetState {
        defer { reads += 1 }
        return states[min(reads, states.count - 1)]
    }

    func install(onUpdate: @escaping @Sendable (SpeechAssetState) -> Void) -> SpeechAssetState {
        installCalls += 1
        return .ready
    }
}

private final class StateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpeechAssetState] = []

    func append(_ value: SpeechAssetState) {
        lock.withLock { storage.append(value) }
    }

    var values: [SpeechAssetState] { lock.withLock { storage } }
}

private final class DurationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Duration] = []

    func append(_ value: Duration) {
        lock.withLock { storage.append(value) }
    }

    var values: [Duration] { lock.withLock { storage } }
}
