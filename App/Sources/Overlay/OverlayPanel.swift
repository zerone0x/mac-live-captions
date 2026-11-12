import AppKit

/// Borderless, click-through panel for the captions.
///
/// - Non-activating and never key or main: showing it or clicking where it is
///   never takes focus from the app you are using.
/// - `ignoresMouseEvents`: clicks go to whatever is underneath (for example
///   the buttons at the top of a meeting window).
/// - Joins all Spaces, including full-screen ones, and stays put in Mission
///   Control.
/// - Level `.mainMenu + 3` (as boring.notch) so it can draw over the menu bar
///   around the notch.
///
/// See docs/DECISIONS.md, 0007.
final class OverlayPanel: NSPanel {
    static func make() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.configure()
        return panel
    }

    private func configure() {
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
