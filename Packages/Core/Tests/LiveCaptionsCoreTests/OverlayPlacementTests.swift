import Foundation
import Testing
@testable import LiveCaptionsCore

@Suite("Overlay placement")
struct OverlayPlacementTests {
    /// 14-inch MacBook Pro at the default scaled resolution: 1512 x 982 points,
    /// 32-point menu bar, 204-point notch.
    static let builtIn = ScreenGeometry(
        frame: OverlayRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: OverlayRect(x: 0, y: 70, width: 1512, height: 880),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: OverlayRect(x: 0, y: 950, width: 654, height: 32),
        auxiliaryTopRightArea: OverlayRect(x: 858, y: 950, width: 654, height: 32)
    )

    /// External 2560 x 1440 display to the right of the built-in one.
    static let external = ScreenGeometry(
        frame: OverlayRect(x: 1512, y: -200, width: 2560, height: 1440),
        visibleFrame: OverlayRect(x: 1512, y: -200, width: 2560, height: 1415)
    )

    @Test("detects the notch from the auxiliary areas and safe-area inset")
    func notchDetection() throws {
        let notch = try #require(Self.builtIn.notch)
        #expect(notch == OverlayRect(x: 654, y: 950, width: 204, height: 32))
        #expect(Self.external.notch == nil)

        var oneSided = Self.builtIn
        oneSided.auxiliaryTopRightArea = nil
        #expect(oneSided.notch == nil)

        var noInset = Self.builtIn
        noInset.safeAreaTop = 0
        #expect(noInset.notch == nil)

        // Zero-width auxiliary areas are not a notch, even if the frame
        // minus them would leave a positive width.
        var zeroLeft = Self.builtIn
        zeroLeft.auxiliaryTopLeftArea = OverlayRect(x: 0, y: 950, width: 0, height: 32)
        #expect(zeroLeft.notch == nil)
        var zeroRight = Self.builtIn
        zeroRight.auxiliaryTopRightArea = OverlayRect(x: 1512, y: 950, width: 0, height: 32)
        #expect(zeroRight.notch == nil)
    }

    @Test("hangs from the notch, centred on it, touching the top edge")
    func notchPlacement() {
        let placement = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: Self.builtIn)
        #expect(placement.style == .notch(notchWidth: 204, notchHeight: 32))
        #expect(placement.frame == OverlayRect(x: 536, y: 890, width: 440, height: 92))
        #expect(placement.frame.midX == 756)
        #expect(placement.frame.maxY == 982)
        #expect(placement.style.topInset == 32)
    }

    @Test("is never narrower than the notch plus its shoulders")
    func narrowCaptions() {
        let placement = OverlayPlacement.place(captionWidth: 100, captionHeight: 60, on: Self.builtIn)
        // 204-point notch plus a 24-point shoulder on each side. A literal, so
        // the test fails if the shoulder constant changes or disappears.
        #expect(placement.frame.width == 252)
        #expect(placement.frame.midX == 756)
    }

    @Test("falls back to a top-centre pill below the menu bar without a notch")
    func pillPlacement() {
        let placement = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: Self.external)
        #expect(placement.style == .pill)
        #expect(placement.style.topInset == 0)
        #expect(placement.frame.midX == Self.external.frame.midX)
        #expect(placement.frame.maxY == Self.external.visibleFrame.maxY - OverlayPlacement.pillGap)
        #expect(placement.frame.height == 60)
    }

    @Test("pill moves to the top edge when the menu bar is hidden")
    func pillWithoutMenuBar() {
        var fullScreen = Self.external
        fullScreen.visibleFrame = fullScreen.frame
        let placement = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: fullScreen)
        #expect(placement.frame.maxY == fullScreen.frame.maxY - OverlayPlacement.pillGap)
    }

    @Test("stays on screen when the captions are wider than the display")
    func clamped() {
        let small = ScreenGeometry(
            frame: OverlayRect(x: 100, y: 0, width: 300, height: 200),
            visibleFrame: OverlayRect(x: 100, y: 0, width: 300, height: 176)
        )
        let placement = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: small)
        #expect(placement.frame.minX == 100)
        #expect(placement.frame.width == 300)
    }

    @Test("bottom position: a centred pill above the Dock, notch or not")
    func bottomPlacement() {
        for screen in [Self.builtIn, Self.external] {
            let placement = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: screen, position: .bottom)
            #expect(placement.style == .pill)
            #expect(placement.frame.midX == screen.frame.midX)
            #expect(placement.frame.minY == screen.visibleFrame.minY + OverlayPlacement.bottomGap)
            #expect(placement.frame.height == 60)
        }
    }

    @Test("bottom position stays on a screen too short for the gap")
    func bottomClamped() {
        let tiny = ScreenGeometry(
            frame: OverlayRect(x: 0, y: 0, width: 300, height: 80),
            visibleFrame: OverlayRect(x: 0, y: 0, width: 300, height: 80)
        )
        let placement = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: tiny, position: .bottom)
        #expect(placement.frame.maxY == 80)
        #expect(placement.frame.width == 300)
    }

    @Test("top position is the default")
    func topIsDefault() {
        let explicit = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: Self.builtIn, position: .top)
        let implicit = OverlayPlacement.place(captionWidth: 440, captionHeight: 60, on: Self.builtIn)
        #expect(explicit == implicit)
    }
}
