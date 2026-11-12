import Foundation
import LiveCaptionsCore
import Speech

/// Checks and installs the en-US speech model with `AssetInventory`.
///
/// Apple docs: assets "are machine-learning models downloaded from Apple's
/// servers and managed by the system"; "Once assets are downloaded, they
/// persist between app launches and are shared between apps." The download is
/// performed by the system, only when `install` is called; recognition itself
/// stays on device.
public struct SystemSpeechAssets: SpeechAssetProvider {
    public let locale: Locale

    public init(locale: Locale = SpeechConfiguration.locale) {
        self.locale = locale
    }

    public func currentState() async -> SpeechAssetState {
        guard let resolved = try? await SpeechConfiguration.resolve(locale) else {
            return .unsupported
        }
        let module = SpeechConfiguration.makeModule(locale: resolved)
        return SpeechAssetState(await AssetInventory.status(forModules: [module]))
    }

    public func install(onUpdate: @escaping @Sendable (SpeechAssetState) -> Void) async -> SpeechAssetState {
        guard let resolved = try? await SpeechConfiguration.resolve(locale) else {
            onUpdate(.unsupported)
            return .unsupported
        }
        let module = SpeechConfiguration.makeModule(locale: resolved)

        let before = SpeechAssetState(await AssetInventory.status(forModules: [module]))
        guard before != .ready, before != .unsupported else {
            onUpdate(before)
            return before
        }

        do {
            // Returns nil when everything is installed already. Reserves the
            // locale if needed (throws if that exceeds the app's reservations).
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                onUpdate(.downloading(fractionCompleted: nil))
                let progress = ProgressBox(request.progress)
                let reporter = Task {
                    while !Task.isCancelled {
                        onUpdate(.downloading(fractionCompleted: progress.fractionCompleted))
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
                defer { reporter.cancel() }
                try await request.downloadAndInstall()
            }
        } catch {
            let failed = SpeechAssetState.failed(message: error.localizedDescription)
            onUpdate(failed)
            return failed
        }

        // `downloadAndInstall()` returns after the first attempt; the system
        // may keep retrying in the background, so report the real status.
        let after = SpeechAssetState(await AssetInventory.status(forModules: [module]))
        onUpdate(after)
        return after
    }
}

/// `Progress` is thread-safe; this box makes that explicit for the reporter task.
private final class ProgressBox: @unchecked Sendable {
    private let progress: Progress

    init(_ progress: Progress) {
        self.progress = progress
    }

    var fractionCompleted: Double { progress.fractionCompleted }
}
