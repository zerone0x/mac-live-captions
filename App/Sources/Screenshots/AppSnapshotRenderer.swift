import AppKit
import LiveCaptionsCore
import SwiftUI

/// Renders the menu status states, the Settings window and the welcome window
/// to PNG files, next to the overlay snapshots (`make screenshots`, #23).
///
/// The menu-bar menu is an `NSMenu` that only exists while it is open, so the
/// status states are drawn as a stand-in: the menu-bar icon and the menu's
/// first items, from the real `SessionStatus` and `SessionPhase`. Settings and
/// the welcome window are the real views, hosted in an off-screen window
/// (`ImageRenderer` cannot draw AppKit-backed controls such as pickers).
@MainActor
enum AppSnapshotRenderer {
    struct MenuState {
        var name: String
        var phase: SessionPhase
        var model: SpeechAssetState = .ready
        var captureTest: AudioCaptureStatus = .idle

        var status: SessionStatus { SessionStatus(phase: phase, model: model, captureTest: captureTest) }
    }

    /// Fixed menu states, one PNG each (`menu-<name>.png`).
    static let menuStates: [MenuState] = [
        MenuState(name: "off", phase: .idle),
        MenuState(name: "off-model-missing", phase: .idle, model: .notInstalled),
        MenuState(name: "busy-checking-model", phase: .checkingModel, model: .checking),
        MenuState(
            name: "busy-downloading",
            phase: .waitingForModel(.downloading(fractionCompleted: 0.42)),
            model: .downloading(fractionCompleted: 0.42)
        ),
        MenuState(name: "busy-starting", phase: .startingCapture),
        MenuState(name: "listening", phase: .listening(.hearing)),
        MenuState(name: "listening-no-audio", phase: .listening(.noAudio)),
        MenuState(name: "listening-reconnecting", phase: .listening(.reconnecting(attempt: 2))),
        MenuState(name: "listening-capture-test", phase: .idle, captureTest: .capturing),
        MenuState(name: "attention-permission", phase: .permissionDenied(.system)),
        MenuState(name: "attention-model-missing", phase: .waitingForModel(.notInstalled), model: .notInstalled),
        MenuState(name: "attention-error", phase: .failed(message: "The audio device disappeared.")),
    ]

    /// Writes `menu-<state>.png`, `settings.png` and `welcome.png` and returns
    /// how many failed.
    static func render(to directory: URL, model: AppModel) -> Int {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var failures = 0
        for state in menuStates {
            let url = directory.appendingPathComponent("menu-\(state.name).png")
            failures += report(writeRendered(MenuStatusSnapshot(state: state), to: url), url)
        }
        let settings = directory.appendingPathComponent("settings.png")
        failures += report(writeHosted(SettingsView(model: model), to: settings), settings)
        let welcome = directory.appendingPathComponent("welcome.png")
        failures += report(writeHosted(OnboardingView(model: model), to: welcome), welcome)
        return failures
    }

    private static func report(_ ok: Bool, _ url: URL) -> Int {
        print(ok ? "rendered \(url.path)" : "failed to render \(url.path)")
        return ok ? 0 : 1
    }

    /// Pure SwiftUI drawing (text, shapes, SF Symbols).
    private static func writeRendered(_ view: some View, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return false }
        return writePNG(NSBitmapImageRep(cgImage: image), to: url)
    }

    /// Real AppKit controls: host the view in an off-screen window and draw
    /// the hosting view into a bitmap.
    private static func writeHosted(_ view: some View, to url: URL) -> Bool {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return false }
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        defer { window.close() }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return writePNG(rep, to: url)
    }

    private static func writePNG(_ rep: NSBitmapImageRep, to url: URL) -> Bool {
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

/// Stand-in for the open menu: a strip of menu bar with the status icon and
/// the menu's first items, as `MenuContent` shows them for this state.
private struct MenuStatusSnapshot: View {
    let state: AppSnapshotRenderer.MenuState

    var body: some View {
        let status = state.status
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: LiveCaptionsApp.symbolName(for: status.indicator))
                    .font(.system(size: 15))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.12)))
                Text("Fri 9:41")
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(white: 0.92))

            VStack(alignment: .leading, spacing: 5) {
                item(status.text, enabled: false)
                if let detail = status.detail {
                    item(detail, enabled: false)
                }
                if status.offersModelDownload {
                    item("Download English Speech Model", enabled: true)
                }
                if status.offersPermissionHelp {
                    item("Open Privacy Settings…", enabled: true)
                    item("Relaunch LiveCaptions", enabled: true)
                }
                Divider()
                item("Start Captions (\(GlobalHotKey.displayName))", enabled: state.phase.canStart)
                item("Stop Captions", enabled: state.phase.canStop)
            }
            .padding(12)
            .frame(width: 300, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.97)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.15)))
            .padding(.trailing, 60)
            .padding(.bottom, 16)
        }
        .frame(width: 480)
        .background(LinearGradient(colors: [Color(white: 0.6), Color(white: 0.4)], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .light)
    }

    private func item(_ text: String, enabled: Bool) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(enabled ? Color.black : Color.black.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}
