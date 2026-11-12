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
struct CaptionOverlayView: View {
    let frame: CaptionFrame
    let style: OverlayStyle
    var metrics = OverlayMetrics()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(frame.lines.map(\.text).joined(separator: " ")))
    }

    private func lineText(_ line: CaptionDisplayLine) -> some View {
        let finalPart = Text(line.finalText).foregroundStyle(.white)
        let volatilePart = Text(line.volatileText).foregroundStyle(.white.opacity(0.5))
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
            .fill(.black)
        case .pill:
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(.black.opacity(0.82))
        }
    }
}
