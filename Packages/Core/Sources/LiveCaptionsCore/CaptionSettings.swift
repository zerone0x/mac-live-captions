import Foundation

/// Caption text size in the overlay.
public enum CaptionFontSize: String, Sendable, Hashable, CaseIterable, Codable {
    case small
    case medium
    case large
    case extraLarge

    public static let `default`: CaptionFontSize = .medium

    /// Point size of the caption font.
    public var points: Double {
        switch self {
        case .small: 13
        case .medium: 15
        case .large: 18
        case .extraLarge: 22
        }
    }

    /// Factor relative to the medium size, which the overlay metrics are
    /// designed for.
    public var scale: Double { points / CaptionFontSize.medium.points }

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

/// Where the overlay sits on the screen with the menu bar.
public enum OverlayPosition: String, Sendable, Hashable, CaseIterable, Codable {
    /// At the notch, or as a pill under the menu bar on displays without one.
    case top
    /// A floating pill near the bottom of the screen, where subtitles usually
    /// are.
    case bottom

    public static let `default`: OverlayPosition = .top

    public var title: String {
        switch self {
        case .top: "Top (at the notch)"
        case .bottom: "Bottom of the screen"
        }
    }
}

/// User settings. Stored as preferences (`UserDefaults`) by the app; no
/// captions, transcripts or audio are ever stored.
public struct CaptionSettings: Sendable, Hashable {
    public var fontSize: CaptionFontSize
    public var position: OverlayPosition
    /// Best effort only (docs/DECISIONS.md, 0009).
    public var hideFromScreenSharing: Bool

    public init(
        fontSize: CaptionFontSize = .default,
        position: OverlayPosition = .default,
        hideFromScreenSharing: Bool = false
    ) {
        self.fontSize = fontSize
        self.position = position
        self.hideFromScreenSharing = hideFromScreenSharing
    }

    /// Preference keys. `hideOverlayFromScreenSharing` predates this type.
    public enum Key {
        public static let fontSize = "captionFontSize"
        public static let position = "overlayPosition"
        public static let hideFromScreenSharing = "hideOverlayFromScreenSharing"
        public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    /// Reads settings from stored preference values; unknown or missing
    /// values fall back to the defaults.
    public init(fontSize: String?, position: String?, hideFromScreenSharing: Bool) {
        self.init(
            fontSize: fontSize.flatMap(CaptionFontSize.init(rawValue:)) ?? .default,
            position: position.flatMap(OverlayPosition.init(rawValue:)) ?? .default,
            hideFromScreenSharing: hideFromScreenSharing
        )
    }
}
