import Foundation

/// One line of the caption overlay.
public struct CaptionLine: Sendable, Hashable, Identifiable {
    public var id: SegmentID
    public var text: String
    public var origin: AudioOrigin
    /// `false` while the recogniser may still revise the text.
    public var isFinal: Bool

    public init(id: SegmentID, text: String, origin: AudioOrigin, isFinal: Bool) {
        self.id = id
        self.text = text
        self.origin = origin
        self.isFinal = isFinal
    }
}

/// What the overlay should show right now. An empty snapshot means "hide".
public struct CaptionSnapshot: Sendable, Hashable {
    public var lines: [CaptionLine]

    public init(lines: [CaptionLine] = []) {
        self.lines = lines
    }

    public static let empty = CaptionSnapshot()

    public var isEmpty: Bool { lines.isEmpty }
}

/// Displays captions. The notch overlay implements this in the app target;
/// tests record the snapshots they receive.
@MainActor
public protocol CaptionPresenter: AnyObject {
    func present(_ snapshot: CaptionSnapshot)
}
