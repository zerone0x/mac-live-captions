import Foundation

/// A rectangle in global screen coordinates (origin at the bottom left, y grows
/// upwards, as in AppKit). Core only imports Foundation, so it has its own
/// small type instead of `CGRect`; the app converts at the boundary.
public struct OverlayRect: Sendable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var midX: Double { x + width / 2 }
    public var minY: Double { y }
    public var maxY: Double { y + height }

    public var description: String { "(\(x), \(y), \(width), \(height))" }
}

/// The parts of an `NSScreen` that overlay placement needs, in global screen
/// coordinates. The app copies these values from `NSScreen`.
public struct ScreenGeometry: Sendable, Hashable {
    public var frame: OverlayRect
    /// `NSScreen.visibleFrame`: the frame minus the menu bar and the Dock.
    public var visibleFrame: OverlayRect
    /// `NSScreen.safeAreaInsets.top`: the notch height on a notched display.
    public var safeAreaTop: Double
    /// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`: the menu
    /// bar space left and right of the notch. `nil` on displays without one.
    public var auxiliaryTopLeftArea: OverlayRect?
    public var auxiliaryTopRightArea: OverlayRect?

    public init(
        frame: OverlayRect,
        visibleFrame: OverlayRect,
        safeAreaTop: Double = 0,
        auxiliaryTopLeftArea: OverlayRect? = nil,
        auxiliaryTopRightArea: OverlayRect? = nil
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    /// The notch, if the display has one: both auxiliary areas exist and the
    /// top safe-area inset is positive (the same test DynamicNotchKit uses).
    public var notch: OverlayRect? {
        guard
            safeAreaTop > 0,
            let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea,
            left.width > 0, right.width > 0
        else { return nil }
        let width = frame.width - left.width - right.width
        guard width > 0 else { return nil }
        return OverlayRect(x: frame.minX + left.width, y: frame.maxY - safeAreaTop, width: width, height: safeAreaTop)
    }
}

/// How the overlay is drawn.
public enum OverlayStyle: Sendable, Hashable {
    /// Hangs from the notch: a black shape as wide as the captions, with the
    /// notch area (`notchHeight` points) left empty at the top.
    case notch(notchWidth: Double, notchHeight: Double)
    /// A floating pill centred under the menu bar, for displays without a notch.
    case pill

    /// Empty space above the captions inside the panel.
    public var topInset: Double {
        switch self {
        case .notch(_, let notchHeight): notchHeight
        case .pill: 0
        }
    }
}

/// Where the overlay panel goes on a screen.
public struct OverlayPlacement: Sendable, Hashable {
    public var style: OverlayStyle
    /// Panel frame in global screen coordinates.
    public var frame: OverlayRect

    public init(style: OverlayStyle, frame: OverlayRect) {
        self.style = style
        self.frame = frame
    }

    /// Extra width on each side of the notch, so the overlay reads as the
    /// notch growing rather than a box stuck under it.
    public static let notchShoulder: Double = 24
    /// Gap between the menu bar and the pill.
    public static let pillGap: Double = 8

    /// Places a caption block of `captionWidth` x `captionHeight` points on
    /// `screen`.
    ///
    /// With a notch, the panel is centred on the notch, touches the top edge
    /// and reserves the notch height above the captions. Without one, it is a
    /// pill centred horizontally just below the menu bar (or the top edge when
    /// the menu bar is hidden, as in full-screen apps).
    public static func place(captionWidth: Double, captionHeight: Double, on screen: ScreenGeometry) -> OverlayPlacement {
        let bounds = screen.frame
        if let notch = screen.notch {
            let width = min(max(captionWidth, notch.width + 2 * notchShoulder), bounds.width)
            let height = notch.height + captionHeight
            let x = clamp(notch.midX - width / 2, bounds.minX, bounds.maxX - width)
            return OverlayPlacement(
                style: .notch(notchWidth: notch.width, notchHeight: notch.height),
                frame: OverlayRect(x: x, y: bounds.maxY - height, width: width, height: height)
            )
        }

        let width = min(captionWidth, bounds.width)
        let top = min(screen.visibleFrame.maxY, bounds.maxY) - pillGap
        let x = clamp(bounds.midX - width / 2, bounds.minX, bounds.maxX - width)
        return OverlayPlacement(
            style: .pill,
            frame: OverlayRect(x: x, y: top - captionHeight, width: width, height: captionHeight)
        )
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        max(low, min(value, high))
    }
}
