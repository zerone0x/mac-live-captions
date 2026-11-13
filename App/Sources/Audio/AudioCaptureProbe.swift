import AppKit
import LiveCaptionsCore
import Observation

/// Debug-only consumer of an `AudioSource`: runs capture on its own and shows
/// the input level and captured seconds, so capture can be checked by hand
/// before the full pipeline is wired in (#11).
@MainActor
@Observable
final class AudioCaptureProbe {
    private(set) var origin: AudioOrigin = .system
    private(set) var status: AudioCaptureStatus = .idle
    private(set) var capturedSeconds: TimeInterval = 0
    private(set) var level: AudioLevel = .silence
    private(set) var chunkCount = 0

    private var source: (any AudioSource)?
    private var task: Task<Void, Never>?
    /// Sources report status on their own threads, in order. One stream and
    /// one main-actor consumer keep that order; a `Task` per update would not
    /// (the menu could show "Capturing audio" after "Not capturing").
    private let statusUpdates: AsyncStream<AudioCaptureStatus>.Continuation

    var isRunning: Bool { task != nil }

    init() {
        let (updates, continuation) = AsyncStream<AudioCaptureStatus>.makeStream()
        statusUpdates = continuation
        Task { [weak self] in
            for await status in updates {
                guard let self else { return }
                self.status = status
            }
        }
    }

    func start(_ origin: AudioOrigin) {
        guard task == nil else { return }
        self.origin = origin
        capturedSeconds = 0
        level = .silence
        chunkCount = 0

        let statusUpdates = self.statusUpdates
        let onStatus: @Sendable (AudioCaptureStatus) -> Void = { status in
            statusUpdates.yield(status)
        }
        let source: any AudioSource = switch origin {
        case .system: SystemAudioSource(onStatus: onStatus)
        case .microphone: MicrophoneAudioSource(onStatus: onStatus)
        }
        self.source = source
        task = Task {
            do {
                let chunks = try await source.start()
                for try await chunk in chunks {
                    record(chunk)
                }
            } catch {
                // The source has already reported the error as its status.
            }
            task = nil
            self.source = nil
            level = .silence
        }
    }

    func stop() {
        guard let source else { return }
        Task { await source.stop() }
    }

    /// Opens the privacy pane that matches a denied permission.
    func openPrivacySettings() {
        let pane = origin == .system ? "Privacy_ScreenCapture" : "Privacy_Microphone"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func record(_ chunk: AudioChunk) {
        capturedSeconds += chunk.duration
        level = AudioLevel(samples: chunk.samples)
        chunkCount += 1
    }

    /// Text meter for the menu, for example "▮▮▮▮▯▯▯▯▯▯ -24 dB".
    var meterText: String {
        let steps = 10
        let filled = Int((level.meterFraction * Double(steps)).rounded())
        let bar = String(repeating: "▮", count: filled) + String(repeating: "▯", count: steps - filled)
        return "\(bar) \(Int(level.decibels.rounded())) dB"
    }
}
