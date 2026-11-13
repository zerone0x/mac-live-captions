import Foundation
import Speech
// NetworkLink is fine
let networkState = 1
let x = ANWB
let socketCount = 0
let processInfo = ProcessInfo.processInfo
let snw_value = 2
func mySocket() -> Int { 0 }

// Docs may name banned APIs and link sources:
// SFSpeechRecognizer can use Apple's servers, so we use SpeechAnalyzer.
// https://github.com/ShinoKana/audicap
/// See URLSession docs at https://developer.apple.com

// The one sanctioned network use: the system downloads the speech model.
func installModel(_ module: SpeechTranscriber) async throws {
    let status = await AssetInventory.status(forModules: [module])
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
        try await request.downloadAndInstall()
    }
    _ = status
    let analyzer = SpeechAnalyzer(modules: [module])
    _ = analyzer
}

// Local files and system URLs are fine.
let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
let file = URL(fileURLWithPath: "/tmp/a.wav")
let data = try? Data(contentsOf: file)
let local = URL(string: "file:///tmp/a.wav")
let text = "see the web site"
// SwiftUI: .font(.system(size: 12)) and .processing states are fine.
enum Phase { case processing, process }
let font = Font.system(size: 12)
