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

    var isRunning: Bool { task != nil }

    func start(_ origin: AudioOrigin) {
        guard task == nil else { return }
        self.origin = origin
        capturedSeconds = 0
        level = .silence
        chunkCount = 0

        // The probe lives as long as the app (owned by `AppModel`), so strong
        // captures are fine here.
        let onStatus: @Sendable (AudioCaptureStatus) -> Void = { status in
            Task { @MainActor in self.status = status }
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
