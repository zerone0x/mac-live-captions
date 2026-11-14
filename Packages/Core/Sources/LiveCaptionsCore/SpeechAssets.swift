import Foundation

/// State of the on-device English (en-US) speech model.
///
/// The speech adapter maps `AssetInventory.Status` onto this:
/// `supported` → `notInstalled`, `downloading` → `downloading`,
/// `installed` → `ready`, `unsupported` → `unsupported`.
public enum SpeechAssetState: Sendable, Hashable {
    /// Not checked yet.
    case checking
    /// This Mac supports the model, but it is not downloaded yet.
    case notInstalled
    /// The system is downloading the model (or waiting to continue).
    /// `fractionCompleted` is 0...1 when known.
    case downloading(fractionCompleted: Double?)
    /// Installed; transcription can start.
    case ready
    /// This Mac or OS cannot run on-device en-US transcription.
    case unsupported
    /// Checking or installing failed.
    case failed(message: String)

    /// Whether transcription can start.
    public var isReady: Bool { self == .ready }

    /// Whether offering "Download" makes sense.
    public var canInstall: Bool {
        switch self {
        case .notInstalled, .failed: true
        case .checking, .downloading, .ready, .unsupported: false
        }
    }

    /// Short status text for the menu.
    public var statusText: String {
        switch self {
        case .checking:
            "Checking English speech model…"
        case .notInstalled:
            "English speech model not installed"
        case .downloading(.some(let fraction)):
            "Downloading English speech model (\(Self.percent(fraction)))…"
        case .downloading(.none):
            "Downloading English speech model…"
        case .ready:
            "English speech model ready"
        case .unsupported:
            "On-device English speech recognition is not supported on this Mac"
        case .failed(let message):
            "Speech model error: \(message)"
        }
    }

    private static func percent(_ fraction: Double) -> String {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return "\(Int((clamped * 100).rounded(.down)))%"
    }
}

/// Checks and installs the on-device speech model.
///
/// The real implementation wraps `AssetInventory`; tests use a fake. The model
/// download is done by the system (not by this app's code) and happens only
/// when `install` is called explicitly.
public protocol SpeechAssetProvider: Sendable {
    /// Current state, without downloading anything.
    func currentState() async -> SpeechAssetState

    /// Downloads and installs the model if needed. Reports intermediate states
    /// (`downloading`) through `onUpdate` and returns the final state.
    func install(onUpdate: @escaping @Sendable (SpeechAssetState) -> Void) async -> SpeechAssetState
}

/// Why a transcriber could not start or continue.
public enum TranscriptionError: Error, Sendable, Hashable, CustomStringConvertible {
    /// This Mac cannot run `SpeechTranscriber` at all.
    case recognizerUnavailable
    /// No supported locale is equivalent to the requested one.
    case localeUnsupported(identifier: String)
    /// The model is not installed yet; install it first.
    case assetsNotReady(SpeechAssetState)
    /// The analyzer reported no usable audio format.
    case noCompatibleAudioFormat
    /// Converting captured audio for the analyzer failed.
    case audioConversionFailed(String)
    /// The analyzer kept failing after the restarts `AnalyzerRestartBudget`
    /// allows (DECISIONS 0024).
    case analyzerStopped(restarts: Int, reason: String)

    public var description: String {
        switch self {
        case .recognizerUnavailable:
            "On-device speech recognition is not available on this Mac"
        case .localeUnsupported(let identifier):
            "Speech recognition does not support \(identifier) on this Mac"
        case .assetsNotReady(let state):
            "The English speech model is not ready (\(state.statusText))"
        case .noCompatibleAudioFormat:
            "The speech model reported no usable audio format"
        case .audioConversionFailed(let reason):
            "Audio conversion failed: \(reason)"
        case .analyzerStopped(let restarts, let reason):
            "Speech recognition stopped after \(restarts) restarts (\(reason)). Turn captions off and on again"
        }
    }
}
