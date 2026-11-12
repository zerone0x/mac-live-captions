import Foundation
import LiveCaptionsCore
import Speech

/// The one recogniser configuration the app uses: en-US, on device
/// (docs/DECISIONS.md, 0003 and 0008).
public enum SpeechConfiguration {
    /// Captions are English only.
    public static let localeIdentifier = "en-US"

    public static var locale: Locale { Locale(identifier: localeIdentifier) }

    /// Builds the transcriber module.
    ///
    /// - `volatileResults`: "Provides tentative results for an audio range in
    ///   addition to the finalized result" (Apple docs), for the live line.
    /// - `fastResults`: "Biases the transcriber towards responsiveness,
    ///   yielding faster but also less accurate results"; captions favour
    ///   latency (Murmo-like).
    /// - No attribute options: the result's `range` already gives the audio
    ///   time range of each phrase.
    static func makeModule(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    /// Resolves `locale` to a locale `SpeechTranscriber` supports on this Mac.
    static func resolve(_ locale: Locale) async throws(TranscriptionError) -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw .recognizerUnavailable
        }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw .localeUnsupported(identifier: locale.identifier(.bcp47))
        }
        return resolved
    }
}

extension SpeechAssetState {
    /// Maps `AssetInventory.Status` onto the app's asset states.
    init(_ status: AssetInventory.Status) {
        switch status {
        case .installed:
            self = .ready
        case .downloading:
            self = .downloading(fractionCompleted: nil)
        case .supported:
            self = .notInstalled
        case .unsupported:
            self = .unsupported
        @unknown default:
            self = .failed(message: "Unknown speech model status")
        }
    }
}
