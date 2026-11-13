import LiveCaptionsCore
import SwiftUI

/// The Settings window: caption size, overlay position and the best-effort
/// screen-sharing option. Settings are the only thing LiveCaptions stores.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Captions") {
                // No `.tag(_:)`: ForEach's `id: \.self` already tags each row
                // with the selection value. `.tag` returns an opaque type that
                // depends on the OS version, so it links compiler-rt's version
                // check, which imports `dlsym` and fails
                // check-linked-frameworks (DECISIONS 0015).
                Picker("Text size", selection: $model.settings.fontSize) {
                    ForEach(CaptionFontSize.allCases, id: \.self) { size in
                        Text(size.title)
                    }
                }
                Picker("Position", selection: $model.settings.position) {
                    ForEach(OverlayPosition.allCases, id: \.self) { position in
                        Text(position.title)
                    }
                }
                Text("On displays without a notch, the top position is a pill under the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Preview with Demo Captions") { model.playDemo() }
                    .disabled(!model.canPlayDemo)
            }

            Section("Screen sharing") {
                Toggle("Hide overlay from screen sharing (best effort)", isOn: $model.settings.hideFromScreenSharing)
                Text("Some apps still capture the overlay. To keep captions private, share a single window instead of the whole screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                LabeledContent("Start or stop captions", value: GlobalHotKey.displayName)
                if !model.hasGlobalShortcut {
                    Text("Another app uses this shortcut, so it is not available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Text(PrivacyCopy.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shared privacy wording for onboarding and Settings.
enum PrivacyCopy {
    static let summary = """
        Speech recognition runs on this Mac. LiveCaptions does not save audio or \
        transcripts; captions disappear when they leave the screen. The only \
        network use is the one-time download of Apple's English speech model, \
        which macOS performs when you ask for it.
        """

    static let modelDownload = """
        macOS downloads Apple's English speech model once, from Apple. This \
        download is the only time LiveCaptions uses the network. After that, \
        recognition works offline.
        """
}
