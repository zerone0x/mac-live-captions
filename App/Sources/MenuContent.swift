import AppKit
import SwiftUI

/// Items of the menu-bar menu (`MenuBarExtra` with the default menu style).
struct MenuContent: View {
    let model: AppModel

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

        CaptureDebugMenu(probe: model.captureProbe)

        Divider()

        Button("Quit LiveCaptions") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
