import AppKit
import LiveCaptionsCore
import SwiftUI

/// Renders the overlay to PNG files so reviewers can see it without a Mac.
///
/// CI runs `LiveCaptions --render-overlay-snapshots <dir>` after the build
/// (`make screenshots`) and uploads the images. The frames come from playing
/// the demo script through the real `CaptionComposer`.
@MainActor
enum OverlaySnapshotRenderer {
    static let argument = "--render-overlay-snapshots"

    /// The output directory if the app was launched to render snapshots.
    static func requestedDirectory(arguments: [String] = CommandLine.arguments) -> URL? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    /// Writes the PNGs and returns how many failed.
    static func render(to directory: URL) -> Int {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let notch = OverlayStyle.notch(notchWidth: 204, notchHeight: 32)
        let frames = demoFrames()
        // Every fixed state must exist, or the screenshots would silently shrink.
        var failures = stateNames.count - frames.count
        if failures > 0 { print("missing overlay states: \(failures)") }
        for (name, frame) in frames {
            // Every state at the default size; the wrap state also at the
            // largest size from Settings, to check that the panel grows with it.
            var sizes: [(prefix: String, size: CaptionFontSize)] = [("", .default)]
            if name == largeFontState { sizes.append(("xl-", .extraLarge)) }
            for (prefix, size) in sizes {
                for (styleName, style) in [("notch", notch), ("pill", OverlayStyle.pill)] {
                    let url = directory.appendingPathComponent("overlay-\(styleName)-\(prefix)\(name).png")
                    let metrics = OverlayMetrics(fontSize: size)
                    if write(scene(frame: frame, style: style, metrics: metrics), to: url) {
                        print("rendered \(url.path)")
                    } else {
                        print("failed to render \(url.path)")
                        failures += 1
                    }
                }
            }
            // Display accommodations (docs/DECISIONS.md, 0018) for the wrap
            // state, which has both finalized and volatile text.
            if name == largeFontState {
                for variant in accessibilityVariants {
                    let url = directory.appendingPathComponent("overlay-\(variant.name)-\(name).png")
                    let style = variant.notch ? notch : OverlayStyle.pill
                    let view = scene(
                        frame: frame,
                        style: style,
                        metrics: OverlayMetrics(fontSize: .default),
                        options: variant.options,
                        lightDesktop: variant.lightDesktop
                    )
                    if write(view, to: url) {
                        print("rendered \(url.path)")
                    } else {
                        print("failed to render \(url.path)")
                        failures += 1
                    }
                }
            }
            // The bottom position (Settings) for the wrap state.
            if name == largeFontState {
                let url = directory.appendingPathComponent("overlay-bottom-\(name).png")
                if write(bottomScene(frame: frame, metrics: OverlayMetrics(fontSize: .default)), to: url) {
                    print("rendered \(url.path)")
                } else {
                    print("failed to render \(url.path)")
                    failures += 1
                }
            }
        }
        return failures
    }

    /// Fixed states taken from the demo played through the real composer:
    /// one finalized line, finalized text plus a volatile tail, a two-line wrap
    /// with a volatile tail, and two finalized lines.
    static let stateNames = ["1-final-line", "2-final-plus-volatile", "3-two-line-wrap-volatile", "4-two-line-final"]

    /// Also rendered with the extra large font (`overlay-*-xl-<state>.png`).
    static let largeFontState = "3-two-line-wrap-volatile"

    /// Increase Contrast and Reduce Transparency renders of `largeFontState`
    /// (`overlay-<name>-<state>.png`). The light-desktop pair shows the
    /// translucent pill at its worst case next to the opaque one.
    static let accessibilityVariants:
        [(name: String, notch: Bool, options: OverlayDisplayOptions, lightDesktop: Bool)] = [
            ("notch-increase-contrast", true, OverlayDisplayOptions(increaseContrast: true), false),
            ("pill-increase-contrast", false, OverlayDisplayOptions(increaseContrast: true), false),
            ("pill-reduce-transparency", false, OverlayDisplayOptions(reduceTransparency: true), false),
            ("pill-light-desktop", false, .standard, true),
            ("pill-reduce-transparency-light-desktop", false, OverlayDisplayOptions(reduceTransparency: true), true),
        ]

    private static func demoFrames() -> [(String, CaptionFrame)] {
        var composer = CaptionComposer()
        var now = 0.0
        var frames: [CaptionFrame] = []
        for step in CaptionDemoScript.english.steps {
            now += step.delay
            frames.append(composer.apply(step.snapshot, at: now))
        }
        let finalLine = frames.first { frame in
            frame.lines.count == 1 && !frame.lines[0].hasVolatileText
        }
        let finalPlusVolatile = frames.first { frame in
            frame.lines.count == 1 && frame.lines[0].hasVolatileText && !frame.lines[0].finalText.isEmpty
        }
        let twoLineWrapVolatile = frames.first { frame in
            frame.lines.count == 2 && frame.lines.contains(where: \.hasVolatileText)
                && frame.lines.contains { line in !line.finalText.isEmpty }
        }
        let twoLineFinal = frames.last { frame in
            frame.lines.count == 2 && !frame.lines.contains(where: \.hasVolatileText)
        }
        return zip(stateNames, [finalLine, finalPlusVolatile, twoLineWrapVolatile, twoLineFinal])
            .compactMap { name, frame in frame.map { (name, $0) } }
    }

    /// The overlay on a strip of fake desktop with a menu bar, at the size the
    /// panel would have.
    private static func scene(
        frame: CaptionFrame,
        style: OverlayStyle,
        metrics: OverlayMetrics,
        options: OverlayDisplayOptions = .standard,
        lightDesktop: Bool = false
    ) -> some View {
        let caption = metrics.captionSize(maxLines: CaptionComposer.Configuration.english.maxLines)
        let panelHeight = caption.height + style.topInset
        let menuBarHeight: CGFloat = 32
        let sceneWidth = max(760, caption.width + 80)
        return ZStack(alignment: .top) {
            if lightDesktop {
                Color(white: 0.97)
            } else {
                LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom)
            }
            Color(white: 0.85).frame(height: menuBarHeight)
            if case .notch(let notchWidth, let notchHeight) = style {
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black)
                    .frame(width: notchWidth, height: notchHeight)
            }
            CaptionOverlayView(frame: frame, style: style, metrics: metrics, displayOptions: options)
                .frame(width: caption.width, height: panelHeight)
                .padding(.top, style == .pill ? menuBarHeight + OverlayPlacement.pillGap : 0)
        }
        .frame(
            width: sceneWidth, height: max(panelHeight, menuBarHeight + OverlayPlacement.pillGap + caption.height) + 40
        )
        .environment(\.colorScheme, .dark)
    }

    /// The pill in the bottom position: `OverlayPlacement.bottomGap` above a
    /// strip of fake Dock at the bottom of the screen.
    private static func bottomScene(frame: CaptionFrame, metrics: OverlayMetrics) -> some View {
        let caption = metrics.captionSize(maxLines: CaptionComposer.Configuration.english.maxLines)
        let dockHeight: CGFloat = 64
        let sceneWidth = max(760, caption.width + 80)
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.8).opacity(0.6))
                .frame(width: sceneWidth * 0.6, height: dockHeight - 8)
                .padding(.bottom, 4)
            CaptionOverlayView(frame: frame, style: .pill, metrics: metrics)
                .frame(width: caption.width, height: caption.height)
                .padding(.bottom, dockHeight + OverlayPlacement.bottomGap)
        }
        .frame(width: sceneWidth, height: caption.height + dockHeight + OverlayPlacement.bottomGap + 40)
        .environment(\.colorScheme, .dark)
    }

    private static func write(_ view: some View, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard
            let image = renderer.cgImage,
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
