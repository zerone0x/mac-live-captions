import Foundation

/// An sRGB colour with straight (not premultiplied) alpha, components 0...1.
/// Core only imports Foundation, so it has its own small type; the app maps it
/// to a SwiftUI `Color`.
public struct OverlayColor: Sendable, Hashable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(white: Double, alpha: Double = 1) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    public static let white = OverlayColor(white: 1)
    public static let black = OverlayColor(white: 0)

    public var isOpaque: Bool { alpha >= 1 }

    /// This colour drawn over `backdrop` (source-over in sRGB, as Core
    /// Graphics blends by default). The result is opaque if `backdrop` is.
    public func over(_ backdrop: OverlayColor) -> OverlayColor {
        let outAlpha = alpha + backdrop.alpha * (1 - alpha)
        guard outAlpha > 0 else { return OverlayColor(white: 0, alpha: 0) }
        func mix(_ top: Double, _ bottom: Double) -> Double {
            (top * alpha + bottom * backdrop.alpha * (1 - alpha)) / outAlpha
        }
        return OverlayColor(
            red: mix(red, backdrop.red),
            green: mix(green, backdrop.green),
            blue: mix(blue, backdrop.blue),
            alpha: outAlpha
        )
    }

    /// WCAG 2.x relative luminance of the colour, ignoring alpha (composite
    /// it with `over(_:)` first).
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio of two opaque colours, 1...21.
    public static func contrastRatio(_ first: OverlayColor, _ second: OverlayColor) -> Double {
        let a = first.relativeLuminance
        let b = second.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public var description: String {
        "rgba(\(red), \(green), \(blue), \(alpha))"
    }
}

/// The macOS display accommodations the overlay follows
/// (System Settings > Accessibility > Display). Reduce Motion is handled
/// where the overlay animates.
public struct OverlayDisplayOptions: Sendable, Hashable {
    /// "Increase contrast".
    public var increaseContrast: Bool
    /// "Reduce transparency".
    public var reduceTransparency: Bool

    public init(increaseContrast: Bool = false, reduceTransparency: Bool = false) {
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
    }

    public static let standard = OverlayDisplayOptions()

    /// Either source turning an option on turns it on (the app reads both
    /// `NSWorkspace` and the SwiftUI environment).
    public func union(_ other: OverlayDisplayOptions) -> OverlayDisplayOptions {
        OverlayDisplayOptions(
            increaseContrast: increaseContrast || other.increaseContrast,
            reduceTransparency: reduceTransparency || other.reduceTransparency
        )
    }
}

/// Colours and text cues of the caption overlay for a set of display options
/// (docs/DECISIONS.md, 0018).
///
/// - Standard: finalized text white, the volatile tail (the recogniser's
///   current guess) white at half opacity; the pill is translucent black.
/// - Reduce Transparency: the pill is opaque black.
/// - Increase Contrast: the pill is opaque black, the volatile tail is
///   brighter (at least 7:1, WCAG AAA) and italic, so it is told apart by
///   shape and not only by brightness (WCAG 1.4.1).
public struct OverlayAppearance: Sendable, Hashable {
    public var options: OverlayDisplayOptions

    public init(options: OverlayDisplayOptions = .standard) {
        self.options = options
    }

    /// Opacity of the pill's black background when nothing asks for an opaque one.
    public static let standardPillOpacity = 0.82
    /// Opacity of the volatile tail without Increase Contrast.
    public static let standardVolatileOpacity = 0.5
    /// Opacity of the volatile tail with Increase Contrast.
    public static let increasedContrastVolatileOpacity = 0.75

    public var finalText: OverlayColor { .white }

    public var volatileText: OverlayColor {
        OverlayColor(
            white: 1,
            alpha: options.increaseContrast
                ? Self.increasedContrastVolatileOpacity
                : Self.standardVolatileOpacity
        )
    }

    /// Volatile text is set in italics (a cue that is not colour).
    public var volatileIsItalic: Bool { options.increaseContrast }

    /// Background of the caption block. The notch style is always opaque
    /// black so it merges with the notch.
    public func background(for style: OverlayStyle) -> OverlayColor {
        switch style {
        case .notch:
            return .black
        case .pill:
            let opaque = options.increaseContrast || options.reduceTransparency
            return OverlayColor(white: 0, alpha: opaque ? 1 : Self.standardPillOpacity)
        }
    }

    /// Contrast of `text` on the overlay background, drawn over `backdrop`
    /// (what is behind the panel; it matters only for a translucent pill).
    public func contrast(of text: OverlayColor, on style: OverlayStyle, over backdrop: OverlayColor) -> Double {
        let background = background(for: style).over(backdrop)
        return OverlayColor.contrastRatio(text.over(background), background)
    }

    /// The lowest contrast of `text` over a white or a black backdrop. For
    /// light text on a dark background a white backdrop is the worst case;
    /// both are checked so the answer does not rest on that argument.
    public func worstContrast(of text: OverlayColor, on style: OverlayStyle) -> Double {
        min(contrast(of: text, on: style, over: .white), contrast(of: text, on: style, over: .black))
    }
}
