import Foundation

/// The parts of an `NSScreen` that overlay placement needs, in global screen
/// coordinates (origin at the bottom left, y grows upwards, as in AppKit).
///
/// Core does not import AppKit; the app copies these values from `NSScreen`.
public struct ScreenGeometry: Sendable, Equatable {
    public var frame: CGRect
    /// `NSScreen.visibleFrame`: the frame minus the menu bar and the Dock.
    public var visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`: the notch height on a notched display.
    public var safeAreaTop: CGFloat
    /// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`: the menu
    /// bar space left and right of the notch. `nil` on displays without one.
    public var auxiliaryTopLeftArea: CGRect?
    public var auxiliaryTopRightArea: CGRect?

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    /// The notch, if the display has one: both auxiliary areas exist and the
    /// top safe-area inset is positive (the same test DynamicNotchKit uses).
    public var notch: CGRect? {
        guard
            safeAreaTop > 0,
            let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea,
            left.width > 0, right.width > 0
        else { return nil }
        let width = frame.width - left.width - right.width
        guard width > 0 else { return nil }
        return CGRect(x: frame.minX + left.width, y: frame.maxY - safeAreaTop, width: width, height: safeAreaTop)
    }
}

/// How the overlay is drawn.
public enum OverlayStyle: Sendable, Equatable {
    /// Hangs from the notch: a black shape as wide as the captions, with the
    /// notch area (`notchHeight` points) left empty at the top.
    case notch(notchWidth: CGFloat, notchHeight: CGFloat)
    /// A floating pill centred under the menu bar, for displays without a notch.
    case pill

    /// Empty space above the captions inside the panel.
    public var topInset: CGFloat {
        switch self {
        case .notch(_, let notchHeight): notchHeight
        case .pill: 0
        }
    }
}

/// Where the overlay panel goes on a screen.
public struct OverlayPlacement: Sendable, Equatable {
    public var style: OverlayStyle
    /// Panel frame in global screen coordinates.
    public var frame: CGRect

    public init(style: OverlayStyle, frame: CGRect) {
        self.style = style
        self.frame = frame
    }

    /// Extra width on each side of the notch, so the overlay reads as the
    /// notch growing rather than a box stuck under it.
    public static let notchShoulder: CGFloat = 24
    /// Gap between the menu bar and the pill.
    public static let pillGap: CGFloat = 8

    /// Places a caption block of `captionSize` on `screen`.
    ///
    /// With a notch, the panel is centred on the notch, touches the top edge
    /// and reserves the notch height above the captions. Without one, it is a
    /// pill centred horizontally just below the menu bar (or the top edge when
    /// the menu bar is hidden, as in full-screen apps).
    public static func place(captionSize: CGSize, on screen: ScreenGeometry) -> OverlayPlacement {
        let bounds = screen.frame
        if let notch = screen.notch {
            let width = min(max(captionSize.width, notch.width + 2 * notchShoulder), bounds.width)
            let height = notch.height + captionSize.height
            let x = clamp(notch.midX - width / 2, bounds.minX, bounds.maxX - width)
            return OverlayPlacement(
                style: .notch(notchWidth: notch.width, notchHeight: notch.height),
                frame: CGRect(x: x, y: bounds.maxY - height, width: width, height: height)
            )
        }

        let width = min(captionSize.width, bounds.width)
        let top = min(screen.visibleFrame.maxY, bounds.maxY) - pillGap
        let x = clamp(bounds.midX - width / 2, bounds.minX, bounds.maxX - width)
        return OverlayPlacement(
            style: .pill,
            frame: CGRect(x: x, y: top - captionSize.height, width: width, height: captionSize.height)
        )
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, high))
    }
}
