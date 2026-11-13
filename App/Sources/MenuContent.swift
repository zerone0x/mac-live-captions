import AppKit
import LiveCaptionsCore
import SwiftUI

/// Items of the menu-bar menu (`MenuBarExtra` with the default menu style).
///
/// The status line comes from `SessionStatus` (Core): it says "Listening"
/// only while audio is really captured.
struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let status = model.status

        Text(status.text)
        if let detail = status.detail {
            Text(detail)
        }

        if status.offersModelDownload {
            Button("Download English Speech Model") { model.downloadModel() }
                .disabled(model.isDownloadingModel)
        }
        if status.offersPermissionHelp {
            Button("Open Privacy Settings…") { model.openPrivacySettings() }
            Button("Relaunch LiveCaptions") { model.relaunch() }
        }

        Divider()

        Button("Start Captions (\(GlobalHotKey.displayName))") { model.start() }
            .keyboardShortcut("s")
            .disabled(!model.phase.canStart)

        Button("Stop Captions") { model.stop() }
            .keyboardShortcut(".")
            .disabled(!model.phase.canStop)

        Divider()

        Button("Settings…") {
            NSApplication.shared.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Welcome and Setup…") {
            NSApplication.shared.activate()
            openWindow(id: OnboardingView.windowID)
        }

        Divider()

        CaptureDebugMenu(probe: model.captureProbe)
            .disabled(model.phase.isActive)

        Button(model.isDemoPlaying ? "Debug: Stop Demo Captions" : "Debug: Demo Captions") { model.toggleDemo() }
            .keyboardShortcut("d")
            .disabled(!model.isDemoPlaying && !model.canPlayDemo)

        Divider()

        Button("Quit LiveCaptions") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
