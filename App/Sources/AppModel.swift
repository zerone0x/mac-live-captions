import AppKit
import Foundation
import LiveCaptionsCore
import LiveCaptionsSpeech
import Observation

/// App-level state and the glue of the caption pipeline.
///
/// The session transitions live in `SessionPhase` and the menu text in
/// `SessionStatus` (both Core, docs/DECISIONS.md 0014). This class performs
/// the effects: it checks and downloads the speech model, runs a
/// `CaptionPipeline` (system audio → `SpeechAnalyzerTranscriber` → overlay)
/// and feeds what happens back in as `SessionEvent`s.
///
/// Captions only live in memory. Nothing (audio, transcript) is written to
/// disk or logged; only the settings are stored as preferences.
@MainActor
@Observable
final class AppModel {
    private(set) var phase: SessionPhase = .idle
    /// The en-US speech model, tracked with or without a session.
    private(set) var modelState: SpeechAssetState = .checking
    private(set) var isDownloadingModel = false

    /// Debug-only audio capture check (#7), separate from the session but
    /// shown as listening while it runs (`SessionStatus`).
    let captureProbe = AudioCaptureProbe()

    /// The notch overlay. Real captions and the demo both draw here; Start
    /// stops the demo, and the demo is off while a session is active.
    let overlay = NotchOverlayController()

    private(set) var isDemoPlaying = false
    @ObservationIgnored private var demoTask: Task<Void, Never>?

    // MARK: Settings (preferences only)

    var settings: CaptionSettings {
        didSet {
            guard settings != oldValue else { return }
            store(settings)
            apply(settings)
        }
    }

    /// Whether the welcome window has been closed once.
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: CaptionSettings.Key.hasCompletedOnboarding) }
    }

    // MARK: Pipeline

    private let assets: any SpeechAssetProvider = SystemSpeechAssets()
    private let transcriber: any Transcriber = SpeechAnalyzerTranscriber()
    @ObservationIgnored private var source: (any AudioSource)?
    @ObservationIgnored private var pipelineTask: Task<Void, Never>?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// Increases with every pipeline start; callbacks from an older pipeline
    /// are dropped.
    @ObservationIgnored private var pipelineGeneration = 0
    @ObservationIgnored private var installGeneration = 0
    @ObservationIgnored private var hotKey: GlobalHotKey?

    init() {
        let defaults = UserDefaults.standard
        let settings = CaptionSettings(
            fontSize: defaults.string(forKey: CaptionSettings.Key.fontSize),
            position: defaults.string(forKey: CaptionSettings.Key.position),
            hideFromScreenSharing: defaults.bool(forKey: CaptionSettings.Key.hideFromScreenSharing)
        )
        self.settings = settings
        hasCompletedOnboarding = defaults.bool(forKey: CaptionSettings.Key.hasCompletedOnboarding)
        apply(settings)

        hotKey = GlobalHotKey { [weak self] in self?.toggleCaptions() }

        // Reads the model state only; nothing is downloaded without a click.
        refreshModelState()

        if CommandLine.arguments.contains(Self.demoArgument) {
            // Give the app a moment to finish launching before the panel opens.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.playDemo(repeating: true)
            }
        }
    }

    /// Launch argument that starts the demo feed on launch and repeats it,
    /// for screenshots of the running app (#23).
    static let demoArgument = "--demo-captions"

    /// What the menu bar shows.
    var status: SessionStatus {
        SessionStatus(phase: phase, model: modelState, captureTest: captureProbe.status)
    }

    /// Whether the global shortcut could be registered.
    var hasGlobalShortcut: Bool { hotKey?.isRegistered ?? false }

    // MARK: Session

    func start() {
        guard phase.canStart else { return }
        // Real captions replace the demo and the capture test.
        stopDemo()
        captureProbe.stop()
        send(.startRequested)
    }

    func stop() {
        send(.stopRequested)
    }

    /// Global shortcut: Start when possible, otherwise Stop.
    func toggleCaptions() {
        if phase.canStart {
            start()
        } else if phase.canStop {
            stop()
        }
    }

    /// Downloads the en-US speech model. macOS downloads it from Apple; this
    /// is the app's only network use, and it happens only on this explicit
    /// request (onboarding or the menu).
    func downloadModel() {
        guard !isDownloadingModel, modelState.canInstall else { return }
        isDownloadingModel = true
        installGeneration += 1
        let generation = installGeneration
        let assets = self.assets
        // The model lives as long as the app, so strong captures are fine.
        Task {
            let final = await assets.install { state in
                Task { @MainActor in
                    guard self.installGeneration == generation, self.isDownloadingModel else { return }
                    self.modelStateChanged(state)
                }
            }
            self.isDownloadingModel = false
            // Progress updates still queued are stale now.
            self.installGeneration += 1
            self.modelStateChanged(final)
        }
    }

    func refreshModelState() {
        let assets = self.assets
        Task { [weak self] in
            let state = await assets.currentState()
            guard let self, !self.isDownloadingModel else { return }
            self.modelStateChanged(state)
        }
    }

    private func send(_ event: SessionEvent) {
        let transition = phase.transition(on: event)
        phase = transition.phase
        for effect in transition.effects {
            perform(effect)
        }
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .checkModel:
            refreshModelState()
        case .startPipeline:
            startPipeline()
        case .stopPipeline:
            stopSource()
        }
    }

    private func stopSource() {
        guard let source else { return }
        Task { await source.stop() }
    }

    private func modelStateChanged(_ state: SpeechAssetState) {
        modelState = state
        send(.modelStateChanged(state))
    }

    /// What one pipeline reports, in the order it happened.
    private enum PipelineUpdate: Sendable {
        /// The audio source reported a status.
        case status(AudioCaptureStatus)
        /// `run()` returned or threw. `permissionDenied` is set when it threw
        /// a denied permission, `model` when the transcriber found the speech
        /// model not ready.
        case ended(failure: String?, permissionDenied: AudioOrigin?, model: SpeechAssetState?)
    }

    /// System audio only (docs/DECISIONS.md, 0014). The microphone stays in
    /// the debug capture test until two origins have a layout.
    ///
    /// The source calls `onStatus` one update at a time, in order, and the
    /// callback must not call back into the source. Status updates and the
    /// end of `run()` go through one stream with one main-actor consumer, so
    /// they are handled in the order they happened; a `Task` per update could
    /// reorder them. Updates after the end of a pipeline, or from an older
    /// pipeline, are dropped.
    private func startPipeline() {
        pipelineGeneration += 1
        let generation = pipelineGeneration
        let (updates, continuation) = AsyncStream<PipelineUpdate>.makeStream()
        let source = SystemAudioSource(onStatus: { status in
            continuation.yield(.status(status))
        })
        self.source = source
        overlay.present(.empty)
        let pipeline = CaptionPipeline(source: source, transcriber: transcriber, presenter: overlay)

        // The single consumer of this pipeline's updates.
        updatesTask = Task { [weak self] in
            for await update in updates {
                guard let self, generation == self.pipelineGeneration else { return }
                switch update {
                case .status(let status):
                    self.send(.captureStatusChanged(status))
                case .ended(let failure, let permissionDenied, let model):
                    self.pipelineEnded(failure: failure, permissionDenied: permissionDenied, model: model)
                    return
                }
            }
        }

        pipelineTask = Task {
            var failure: String?
            var permissionDenied: AudioOrigin?
            var model: SpeechAssetState?
            do {
                try await pipeline.run()
            } catch let error as AudioCaptureError {
                if case .permissionDenied(let origin) = error {
                    permissionDenied = origin
                }
                failure = error.localizedDescription
            } catch let error as TranscriptionError {
                if case .assetsNotReady(let state) = error {
                    model = state
                }
                failure = error.description
            } catch {
                failure = error.localizedDescription
            }
            // After every status the source reported for this run.
            continuation.yield(.ended(failure: failure, permissionDenied: permissionDenied, model: model))
            continuation.finish()
        }
    }

    private func pipelineEnded(failure: String?, permissionDenied: AudioOrigin?, model: SpeechAssetState?) {
        if let model {
            modelStateChanged(model)
        }
        // The source reports a denied permission as its status before it
        // throws; only fill it in if that status did not arrive.
        if let permissionDenied, !isPermissionDenied {
            send(.captureStatusChanged(.permissionDenied(permissionDenied)))
        }
        // `.stopPipeline` effects of these transitions (a pipeline that died
        // while listening) still reach this pipeline's source; it is released
        // only afterwards.
        send(.pipelineEnded(failure: failure))
        source = nil
        pipelineTask = nil
        updatesTask = nil
    }

    private var isPermissionDenied: Bool {
        if case .permissionDenied = phase { true } else { false }
    }

    // MARK: Permission

    /// Whether Screen & System Audio Recording is granted. Changes only take
    /// effect after a relaunch.
    var hasSystemAudioPermission: Bool { SystemAudioSource.hasPermission }

    /// Opens the Screen & System Audio Recording pane of System Settings.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quits and reopens the app, so a newly granted permission applies.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: Settings

    private func store(_ settings: CaptionSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.fontSize.rawValue, forKey: CaptionSettings.Key.fontSize)
        defaults.set(settings.position.rawValue, forKey: CaptionSettings.Key.position)
        defaults.set(settings.hideFromScreenSharing, forKey: CaptionSettings.Key.hideFromScreenSharing)
    }

    private func apply(_ settings: CaptionSettings) {
        overlay.fontSize = settings.fontSize
        overlay.position = settings.position
        overlay.hidesFromScreenSharing = settings.hideFromScreenSharing
    }

    // MARK: Demo captions

    /// The demo draws into the same overlay as real captions, so it is only
    /// available while no session is active.
    var canPlayDemo: Bool { !phase.isActive }

    func toggleDemo() {
        if isDemoPlaying {
            stopDemo()
        } else {
            playDemo()
        }
    }

    /// Plays the scripted English feed into the overlay, so it can be seen
    /// without audio or permissions.
    ///
    /// With `repeating`, the feed starts over (from an empty overlay) until
    /// stopped.
    func playDemo(_ script: CaptionDemoScript = .english, repeating: Bool = false) {
        guard canPlayDemo else { return }
        demoTask?.cancel()
        overlay.present(.empty)
        isDemoPlaying = true
        demoTask = Task { [weak self] in
            repeat {
                for step in script.steps {
                    try? await Task.sleep(for: .seconds(step.delay))
                    guard !Task.isCancelled else { return }
                    self?.overlay.present(step.snapshot)
                }
                if repeating {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.overlay.present(.empty)
                }
            } while repeating && !Task.isCancelled
            // Leave the last caption up; the overlay collapses when idle.
            self?.isDemoPlaying = false
            self?.demoTask = nil
        }
    }

    func stopDemo() {
        guard isDemoPlaying || demoTask != nil else { return }
        demoTask?.cancel()
        demoTask = nil
        isDemoPlaying = false
        overlay.present(.empty)
    }
}
