import LiveCaptionsCore
import SwiftUI

/// Menu-bar-only app (LSUIElement): no Dock icon, no main window.
@main
struct LiveCaptionsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.phase == .running ? "captions.bubble.fill" : "captions.bubble")
                .accessibilityLabel("LiveCaptions")
        }
    }
}
