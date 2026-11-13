import Testing
@testable import LiveCaptionsCore

@Suite("CaptionSettings")
struct CaptionSettingsTests {
    @Test("defaults: medium text at the top, sharing not hidden")
    func defaults() {
        let settings = CaptionSettings()
        #expect(settings.fontSize == .medium)
        #expect(settings.position == .top)
        #expect(!settings.hideFromScreenSharing)
        #expect(CaptionFontSize.medium.scale == 1)
    }

    @Test("stored values round-trip; unknown or missing ones fall back to defaults")
    func storedValues() {
        let stored = CaptionSettings(fontSize: "large", position: "bottom", hideFromScreenSharing: true)
        #expect(stored == CaptionSettings(fontSize: .large, position: .bottom, hideFromScreenSharing: true))

        let unknown = CaptionSettings(fontSize: "huge", position: nil, hideFromScreenSharing: false)
        #expect(unknown == CaptionSettings())
    }

    @Test("font sizes grow monotonically")
    func fontSizes() {
        let points = CaptionFontSize.allCases.map(\.points)
        #expect(points == points.sorted())
        #expect(Set(points).count == points.count)
    }
}
