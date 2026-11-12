import Foundation
import Testing
@testable import LiveCaptionsCore

@Suite("Speech assets")
struct SpeechAssetTests {
    @Test(
        "readiness and install offer per state",
        arguments: [
            (SpeechAssetState.checking, false, false),
            (.notInstalled, false, true),
            (.downloading(fractionCompleted: 0.5), false, false),
            (.downloading(fractionCompleted: nil), false, false),
            (.ready, true, false),
            (.unsupported, false, false),
            (.failed(message: "x"), false, true),
        ]
    )
    func flags(state: SpeechAssetState, isReady: Bool, canInstall: Bool) {
        #expect(state.isReady == isReady)
        #expect(state.canInstall == canInstall)
    }

    @Test(
        "status text",
        arguments: [
            (SpeechAssetState.checking, "Checking English speech model…"),
            (.notInstalled, "English speech model not installed"),
            (.downloading(fractionCompleted: nil), "Downloading English speech model…"),
            (.downloading(fractionCompleted: 0.426), "Downloading English speech model (42%)…"),
            (.downloading(fractionCompleted: 1.7), "Downloading English speech model (100%)…"),
            (.downloading(fractionCompleted: -0.2), "Downloading English speech model (0%)…"),
            (.downloading(fractionCompleted: .nan), "Downloading English speech model (0%)…"),
            (.ready, "English speech model ready"),
            (.unsupported, "On-device English speech recognition is not supported on this Mac"),
            (.failed(message: "disk full"), "Speech model error: disk full"),
        ]
    )
    func statusText(state: SpeechAssetState, text: String) {
        #expect(state.statusText == text)
    }

    @Test("transcription errors describe themselves")
    func errorDescriptions() {
        #expect(TranscriptionError.assetsNotReady(.notInstalled).description
            == "The English speech model is not ready (English speech model not installed)")
        #expect(TranscriptionError.localeUnsupported(identifier: "en-US").description.contains("en-US"))
        #expect(TranscriptionError.audioConversionFailed("bad format").description.contains("bad format"))
    }

    @Test("a fake provider walks from not installed to ready and reports progress")
    func fakeProviderInstall() async {
        let assets = ScriptedSpeechAssets(
            initial: .notInstalled,
            installSteps: [.downloading(fractionCompleted: 0), .downloading(fractionCompleted: 0.5)],
            installResult: .ready
        )
        #expect(await assets.currentState() == .notInstalled)

        let updates = UpdateLog()
        let final = await assets.install { updates.append($0) }

        #expect(final == .ready)
        #expect(await assets.currentState() == .ready)
        #expect(updates.values == [
            .downloading(fractionCompleted: 0),
            .downloading(fractionCompleted: 0.5),
            .ready,
        ])
    }
}
