import Foundation
import LiveCaptionsCore
import SwiftUI

/// Menu-bar-only app (LSUIElement): no Dock icon, no main window.
@main
struct LiveCaptionsApp: App {
    @State private var model = AppModel()

    init() {
        // CI hook: render overlay screenshots and quit (see `make screenshots`).
        if let directory = OverlaySnapshotRenderer.requestedDirectory() {
            let failures = OverlaySnapshotRenderer.render(to: directory)
            exit(failures == 0 ? 0 : 1)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.phase == .running ? "captions.bubble.fill" : "captions.bubble")
                .accessibilityLabel("LiveCaptions")
        }
    }
}
