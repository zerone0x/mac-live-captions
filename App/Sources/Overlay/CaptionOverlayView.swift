import LiveCaptionsCore
import SwiftUI

/// Sizes of the caption block for one font size. The block always reserves
/// room for two lines so the panel never resizes while text streams in.
/// The values are designed for the medium size (15 pt) and scale with it.
struct OverlayMetrics: Equatable {
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let lineSpacing: CGFloat
    /// Fits a typical 42-character line of the system font; lines of wide
    /// characters shrink slightly instead of rewrapping.
    let textWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat

    init(fontSize: CaptionFontSize = .default) {
        let scale = CGFloat(fontSize.scale)
        self.fontSize = CGFloat(fontSize.points)
        lineHeight = (20 * scale).rounded()
        lineSpacing = 2
        textWidth = (340 * scale).rounded()
        horizontalPadding = 18
        verticalPadding = 9
        cornerRadius = 16
    }

    func captionSize(maxLines: Int) -> CGSize {
        let lines = CGFloat(maxLines)
        return CGSize(
            width: textWidth + 2 * horizontalPadding,
            height: lines * lineHeight + (lines - 1) * lineSpacing + 2 * verticalPadding
        )
    }
}

/// The caption overlay: finalized text in white, the volatile tail lighter.
/// Follows Increase Contrast and Reduce Transparency through
/// `OverlayAppearance` (docs/DECISIONS.md, 0018).
struct CaptionOverlayView: View {
    let frame: CaptionFrame
    let style: OverlayStyle
    var metrics = OverlayMetrics()
    /// Display options read from `NSWorkspace` by the controller (or forced
    /// by the snapshot renderer). Combined with the SwiftUI environment, so
    /// either source turns an option on.
    var displayOptions: OverlayDisplayOptions = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var appearance: OverlayAppearance {
        let environment = OverlayDisplayOptions(
            increaseContrast: colorSchemeContrast == .increased,
            reduceTransparency: reduceTransparency
        )
        return OverlayAppearance(options: displayOptions.union(environment))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: style.topInset)
            VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                ForEach(frame.lines) { line in
                    lineText(line)
                        .frame(height: metrics.lineHeight)
                        .transition(.opacity)
                }
            }
            .frame(width: metrics.textWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: frame.lines.first?.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        // VoiceOver: one static text element, label "Live captions", value
        // the visible text. It is reachable (for example by Braille display
        // users) but never announces itself: spoken announcements of every
        // partial result would talk over the audio being captioned
        // (docs/DECISIONS.md, 0018).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Live captions"))
        .accessibilityValue(Text(frame.lines.map(\.text).joined(separator: " ")))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func lineText(_ line: CaptionDisplayLine) -> some View {
        let appearance = appearance
        let finalPart = Text(line.finalText).foregroundStyle(Color(appearance.finalText))
        let volatilePart = Text(line.volatileText)
            .italic(appearance.volatileIsItalic)
            .foregroundStyle(Color(appearance.volatileText))
        return Text("\(finalPart)\(volatilePart)")
            .font(.system(size: metrics.fontSize, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .notch:
            // Square top so it merges with the notch, round bottom corners.
            UnevenRoundedRectangle(
                bottomLeadingRadius: metrics.cornerRadius,
                bottomTrailingRadius: metrics.cornerRadius,
                style: .continuous
            )
            .fill(Color(appearance.background(for: style)))
        case .pill:
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(Color(appearance.background(for: style)))
        }
    }
}

extension Color {
    init(_ color: OverlayColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
