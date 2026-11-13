import Foundation
import LiveCaptionsCore
import SwiftUI

/// Menu-bar-only app (LSUIElement): no Dock icon. Besides the menu it has a
/// Settings window and a welcome window that opens on first launch.
@main
struct LiveCaptionsApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        // CI hook: render screenshots and quit (see `make screenshots`).
        if let directory = OverlaySnapshotRenderer.requestedDirectory() {
            let failures = OverlaySnapshotRenderer.render(to: directory)
                + AppSnapshotRenderer.render(to: directory, model: model)
            exit(failures == 0 ? 0 : 1)
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: Self.symbolName(for: model.status.indicator))
                .accessibilityLabel("LiveCaptions: \(model.status.text)")
        }

        Window("Welcome to LiveCaptions", id: OnboardingView.windowID) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.hasCompletedOnboarding ? .suppressed : .presented)

        Settings {
            SettingsView(model: model)
        }
    }

    /// Filled only while audio is captured, so the icon never claims to
    /// listen when nothing does.
    static func symbolName(for indicator: SessionStatus.Indicator) -> String {
        switch indicator {
        case .off: "captions.bubble"
        case .busy: "ellipsis.bubble"
        case .listening: "captions.bubble.fill"
        case .attention: "exclamationmark.bubble"
        }
    }
}
