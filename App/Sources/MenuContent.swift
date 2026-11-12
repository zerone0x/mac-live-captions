import AppKit
import SwiftUI

/// Items of the menu-bar menu (`MenuBarExtra` with the default menu style).
struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Text(model.phase.statusText)

        Divider()

        Button("Start Captions") { model.start() }
            .keyboardShortcut("s")
            .disabled(!model.phase.canStart)

        Button("Stop Captions") { model.stop() }
            .keyboardShortcut(".")
            .disabled(!model.phase.canStop)

        Divider()

        Toggle("Hide Overlay from Screen Sharing (Best Effort)", isOn: $model.hideOverlayFromScreenSharing)

        Section("Debug") {
            Button(model.isDemoPlaying ? "Stop Demo Captions" : "Demo Captions") { model.toggleDemo() }
                .keyboardShortcut("d")
        }

        Divider()

        Button("Quit LiveCaptions") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
