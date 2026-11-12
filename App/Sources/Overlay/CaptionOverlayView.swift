import LiveCaptionsCore
import SwiftUI

/// Fixed sizes of the caption block. The block always reserves room for two
/// lines so the panel never resizes while text streams in.
enum OverlayMetrics {
    static let fontSize: CGFloat = 15
    static let lineHeight: CGFloat = 20
    static let lineSpacing: CGFloat = 2
    /// Wide enough for 42 characters of the system font at 15 pt; lines that
    /// are still too wide shrink slightly instead of rewrapping.
    static let textWidth: CGFloat = 400
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 9
    static let cornerRadius: CGFloat = 16

    static func captionSize(maxLines: Int) -> CGSize {
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: style.topInset)
            VStack(alignment: .leading, spacing: OverlayMetrics.lineSpacing) {
                ForEach(frame.lines) { line in
                    lineText(line)
                        .frame(height: OverlayMetrics.lineHeight)
                        .transition(.opacity)
                }
            }
            .frame(width: OverlayMetrics.textWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, OverlayMetrics.horizontalPadding)
            .padding(.vertical, OverlayMetrics.verticalPadding)
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
            .font(.system(size: OverlayMetrics.fontSize, weight: .medium))
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
                bottomLeadingRadius: OverlayMetrics.cornerRadius,
                bottomTrailingRadius: OverlayMetrics.cornerRadius,
                style: .continuous
            )
            .fill(.black)
        case .pill:
            RoundedRectangle(cornerRadius: OverlayMetrics.cornerRadius, style: .continuous)
                .fill(.black.opacity(0.82))
        }
    }
}
