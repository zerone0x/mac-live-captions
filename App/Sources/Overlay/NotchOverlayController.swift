import AppKit
import LiveCaptionsCore
import Observation
import SwiftUI

/// State the overlay view renders.
@MainActor
@Observable
final class OverlayViewModel {
    var frame: CaptionFrame = .empty
    var style: OverlayStyle = .pill
    var metrics = OverlayMetrics()
    var displayOptions = OverlayDisplayOptions.standard
}

private struct OverlayRootView: View {
    let model: OverlayViewModel

    var body: some View {
        CaptionOverlayView(
            frame: model.frame,
            style: model.style,
            metrics: model.metrics,
            displayOptions: model.displayOptions
        )
    }
}

/// Shows caption snapshots in a panel at the notch of the menu-bar screen
/// (or as a pill on displays without a notch, or near the bottom of the
/// screen when the user picks that position) and hides it when idle.
///
/// Layout and timing decisions come from `CaptionComposer` and
/// `OverlayPlacement` in Core; this class only drives AppKit.
@MainActor
final class NotchOverlayController: CaptionPresenter {
    private var composer = CaptionComposer()
    private let model = OverlayViewModel()
    private var panel: OverlayPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var displayOptionsObserver: (any NSObjectProtocol)?
    private var collapseTask: Task<Void, Never>?
    private var isShowing = false
    private let clockStart = ContinuousClock.now

    /// Best effort only: sets `NSWindow.sharingType` to `.none`. Apple calls
    /// that a legacy constant and ScreenCaptureKit-based capture may ignore it
    /// (docs/research/ux-and-privacy.md, 1.4). Sharing a single window instead
    /// of the whole screen is the reliable way to keep captions private.
    var hidesFromScreenSharing = false {
        didSet { panel?.sharingType = hidesFromScreenSharing ? .none : .readOnly }
    }

    /// Caption text size (Settings).
    var fontSize: CaptionFontSize = .default {
        didSet {
            guard fontSize != oldValue else { return }
            model.metrics = OverlayMetrics(fontSize: fontSize)
            reposition()
        }
    }

    /// Top (notch) or bottom of the screen (Settings).
    var position: OverlayPosition = .default {
        didSet {
            guard position != oldValue else { return }
            reposition()
        }
    }

    init() {}

    // MARK: CaptionPresenter

    func present(_ snapshot: CaptionSnapshot) {
        let now = self.now
        model.frame = composer.apply(snapshot, at: now)
        update(at: now)
    }

    // MARK: Visibility

    private var now: TimeInterval {
        let elapsed = ContinuousClock.now - clockStart
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private func update(at now: TimeInterval) {
        collapseTask?.cancel()
        collapseTask = nil
        guard composer.isExpanded(at: now), let deadline = composer.collapseDeadline else {
            hide()
            return
        }
        show()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline - now)))
            guard !Task.isCancelled, let self else { return }
            self.update(at: self.now)
        }
    }

    private func show() {
        let panel = makePanelIfNeeded()
        reposition()
        guard !isShowing else { return }
        isShowing = true
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.reduceMotion ? 0 : 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard isShowing, let panel else { return }
        isShowing = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.reduceMotion ? 0 : 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new caption may have arrived during the fade.
                guard let self, !self.isShowing else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var currentDisplayOptions: OverlayDisplayOptions {
        OverlayDisplayOptions(
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    // MARK: Panel and placement

    private func makePanelIfNeeded() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel.make()
        let hosting = NSHostingView(rootView: OverlayRootView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.sharingType = hidesFromScreenSharing ? .none : .readOnly
        self.panel = panel

        // Increase Contrast / Reduce Transparency can change while the app
        // runs; the SwiftUI environment of a hosting view in a non-activating
        // panel is not guaranteed to follow, so read NSWorkspace as well.
        model.displayOptions = Self.currentDisplayOptions
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.displayOptions = Self.currentDisplayOptions }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        return panel
    }

    /// Places the panel on the screen that has the menu bar. That is
    /// `NSScreen.screens.first`, not `NSScreen.main` (the screen with the key
    /// window, which moves with focus).
    private func reposition() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let geometry = ScreenGeometry(
            frame: OverlayRect(screen.frame),
            visibleFrame: OverlayRect(screen.visibleFrame),
            safeAreaTop: Double(screen.safeAreaInsets.top),
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea.map { OverlayRect($0) },
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea.map { OverlayRect($0) }
        )
        let caption = model.metrics.captionSize(maxLines: composer.configuration.maxLines)
        let placement = OverlayPlacement.place(
            captionWidth: Double(caption.width),
            captionHeight: Double(caption.height),
            on: geometry,
            position: position
        )
        if model.style != placement.style {
            model.style = placement.style
        }
        let frame = NSRect(placement.frame)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }
}

extension OverlayRect {
    init(_ rect: NSRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

extension NSRect {
    init(_ rect: OverlayRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
