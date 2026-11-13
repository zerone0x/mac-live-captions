import Testing

@testable import LiveCaptionsCore

/// Contrast of the caption overlay (docs/DECISIONS.md, 0018). Pure colour
/// math: the overlay draws white text on black, so the ratios can be computed
/// without rendering. A translucent pill is checked over a white and a black
/// desktop, the worst case being the lower of the two.
@Suite("OverlayAppearance (contrast)")
struct OverlayAppearanceTests {
    static let notch = OverlayStyle.notch(notchWidth: 204, notchHeight: 32)
    static let standard = OverlayAppearance()
    static let increased = OverlayAppearance(options: OverlayDisplayOptions(increaseContrast: true))
    static let reduced = OverlayAppearance(options: OverlayDisplayOptions(reduceTransparency: true))
    /// WCAG AA for normal text, and AAA (enhanced).
    static let aa = 4.5
    static let aaa = 7.0

    // MARK: Colour math

    @Test("contrast ratio matches the WCAG reference values")
    func wcagReference() {
        #expect(OverlayColor.contrastRatio(.white, .black) == 21)
        #expect(OverlayColor.contrastRatio(.black, .black) == 1)
        // #777777 on white is the classic "just below AA" grey (4.48:1).
        let grey = OverlayColor(white: Double(0x77) / 255)
        #expect(abs(OverlayColor.contrastRatio(grey, .white) - 4.48) < 0.01)
        // Order of the arguments does not matter.
        #expect(OverlayColor.contrastRatio(grey, .white) == OverlayColor.contrastRatio(.white, grey))
    }

    @Test("compositing: half white over black is mid grey; opaque colours hide the backdrop")
    func compositing() {
        let half = OverlayColor(white: 1, alpha: 0.5).over(.black)
        #expect(abs(half.red - 0.5) < 1e-9 && half.isOpaque)
        #expect(OverlayColor.white.over(.black) == .white)
        let pill = OverlayColor(white: 0, alpha: 0.82).over(.white)
        #expect(abs(pill.red - 0.18) < 1e-9)
    }

    // MARK: Standard appearance

    @Test("standard: final text is far above AAA on both styles")
    func standardFinal() {
        let s = Self.standard
        #expect(s.worstContrast(of: s.finalText, on: Self.notch) == 21)
        #expect(s.worstContrast(of: s.finalText, on: .pill) > 13)
    }

    @Test("standard: volatile text stays above AA, even on a translucent pill over white")
    func standardVolatile() {
        let s = Self.standard
        let notch = s.worstContrast(of: s.volatileText, on: Self.notch)
        let pill = s.worstContrast(of: s.volatileText, on: .pill)
        #expect(abs(notch - 5.28) < 0.01)
        #expect(abs(pill - 4.62) < 0.01)
        #expect(pill >= Self.aa)
        // The worst case for the pill is a white desktop.
        #expect(pill == s.contrast(of: s.volatileText, on: .pill, over: .white))
        #expect(!s.volatileIsItalic)
        #expect(!s.background(for: .pill).isOpaque)
    }

    // MARK: Increase Contrast

    @Test("increase contrast: opaque pill, italic volatile text at AAA on every background")
    func increasedContrast() {
        let s = Self.increased
        #expect(s.background(for: .pill).isOpaque)
        #expect(s.background(for: Self.notch).isOpaque)
        #expect(s.volatileIsItalic)
        for style in [Self.notch, OverlayStyle.pill] {
            #expect(s.worstContrast(of: s.finalText, on: style) == 21)
            let volatile = s.worstContrast(of: s.volatileText, on: style)
            #expect(volatile >= Self.aaa, "\(style)")
            #expect(abs(volatile - 11.45) < 0.01, "\(style): \(volatile)")
            // Brighter than the standard guess, but still visibly not final.
            #expect(volatile > Self.standard.worstContrast(of: Self.standard.volatileText, on: style))
            #expect(volatile < 21)
        }
    }

    // MARK: Reduce Transparency

    @Test("reduce transparency: opaque pill, backdrop no longer changes the contrast")
    func reducedTransparency() {
        let s = Self.reduced
        #expect(s.background(for: .pill).isOpaque)
        let overWhite = s.contrast(of: s.volatileText, on: .pill, over: .white)
        let overBlack = s.contrast(of: s.volatileText, on: .pill, over: .black)
        #expect(overWhite == overBlack)
        #expect(abs(overWhite - 5.28) < 0.01)
        #expect(!s.volatileIsItalic)
    }

    @Test("options combine with OR")
    func union() {
        let a = OverlayDisplayOptions(increaseContrast: true)
        let b = OverlayDisplayOptions(reduceTransparency: true)
        #expect(a.union(b) == OverlayDisplayOptions(increaseContrast: true, reduceTransparency: true))
        #expect(OverlayDisplayOptions.standard.union(.standard) == .standard)
    }

    // MARK: Menu bar item

    @Test("the menu bar item's VoiceOver label carries the status line")
    func statusAccessibility() {
        let listening = SessionStatus(phase: .listening(.hearing), model: .ready)
        #expect(listening.accessibilityLabel == "LiveCaptions, Listening")
        #expect(listening.accessibilityValue == "")
        let off = SessionStatus(phase: .idle, model: .ready)
        #expect(off.accessibilityLabel == "LiveCaptions, Not listening")
        let denied = SessionStatus(phase: .permissionDenied(.system), model: .ready)
        #expect(denied.accessibilityLabel == "LiveCaptions, Waiting for permission")
        #expect(denied.accessibilityValue == denied.detail)
        #expect(!denied.accessibilityValue.isEmpty)
    }
}
