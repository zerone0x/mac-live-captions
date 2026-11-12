import AppKit
import LiveCaptionsCore
import SwiftUI

/// First-run window: the speech model download, the system audio permission,
/// then Start. Opens on first launch and from "Welcome and Setup…".
struct OnboardingView: View {
    static let windowID = "onboarding"

    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Read when the window appears; macOS applies a new grant only after a
    /// relaunch, so it does not change while the app runs.
    @State private var hasPermission = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to LiveCaptions")
                    .font(.title2.bold())
                Text("Live English captions for the audio your Mac plays, shown at the notch. Speech recognition runs on this Mac; audio and transcripts are never saved.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            step(number: 1, title: "English speech model", done: model.modelState.isReady) {
                Text(model.modelState.statusText)
                Text(PrivacyCopy.modelDownload)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.modelState.canInstall {
                    Button("Download English Speech Model") { model.downloadModel() }
                        .disabled(model.isDownloadingModel)
                }
            }

            step(number: 2, title: "Screen & System Audio Recording", done: hasPermission) {
                if hasPermission {
                    Text("Allowed. LiveCaptions only listens while captions are on.")
                } else {
                    Text("LiveCaptions needs this permission to hear the audio your Mac plays. It does not record your screen.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Turn on LiveCaptions in System Settings > Privacy & Security > Screen & System Audio Recording, then relaunch the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Ask for Permission") { requestPermission() }
                        Button("Open Privacy Settings…") { model.openPrivacySettings() }
                        Button("Relaunch") { model.relaunch() }
                    }
                }
            }

            step(number: 3, title: "Start captions", done: model.phase.isCapturing) {
                Text("Play a video or join a call; captions appear at the top of the screen. Start and stop from the menu bar or with \(GlobalHotKey.displayName) from any app.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Close") { finish() }
                Button("Start Captions") {
                    model.start()
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.phase.canStart)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            hasPermission = model.hasSystemAudioPermission
            model.refreshModelState()
            NSApplication.shared.activate()
        }
        .onDisappear {
            model.hasCompletedOnboarding = true
        }
    }

    private func step(
        number: Int,
        title: String,
        done: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.secondary)
                .accessibilityLabel(done ? "Done" : "Step \(number)")
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    private func requestPermission() {
        // Shows the system prompt the first time; later it only reports the
        // current answer. A grant applies after a relaunch.
        hasPermission = CGRequestScreenCaptureAccess()
    }

    private func finish() {
        model.hasCompletedOnboarding = true
        dismiss()
    }
}
