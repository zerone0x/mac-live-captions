import LiveCaptionsCore
import SwiftUI

/// "Debug: Audio Capture" submenu. Lets the owner check system audio (and the
/// optional microphone) capture by hand until the pipeline is wired (#11).
struct CaptureDebugMenu: View {
    let probe: AudioCaptureProbe

    var body: some View {
        Menu("Debug: Audio Capture") {
            Text(probe.status.statusText)
            if probe.isRunning {
                Text("Level \(probe.meterText)")
                Text("Captured \(probe.capturedSeconds.formatted(.number.precision(.fractionLength(1)))) s (\(probe.chunkCount) chunks)")
                Button("Stop Capture Test") { probe.stop() }
            } else {
                Button("Test System Audio Capture") { probe.start(.system) }
                Button("Test Microphone Capture") { probe.start(.microphone) }
            }
            if case .permissionDenied = probe.status {
                Button("Open Privacy Settings…") { probe.openPrivacySettings() }
            }
        }
    }
}
