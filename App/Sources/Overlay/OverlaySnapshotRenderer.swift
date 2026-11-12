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
        var failures = 0
        for (name, frame) in frames {
            for (styleName, style) in [("notch", notch), ("pill", OverlayStyle.pill)] {
                let url = directory.appendingPathComponent("overlay-\(styleName)-\(name).png")
                if write(scene(frame: frame, style: style), to: url) {
                    print("rendered \(url.path)")
                } else {
                    print("failed to render \(url.path)")
                    failures += 1
                }
            }
        }
        return failures
    }

    /// Frames at interesting points of the demo: volatile text mid-sentence,
    /// two lines with a volatile tail, and all text finalized.
    private static func demoFrames() -> [(String, CaptionFrame)] {
        var composer = CaptionComposer()
        var now = 0.0
        var frames: [CaptionFrame] = []
        for step in CaptionDemoScript.english.steps {
            now += step.delay
            frames.append(composer.apply(step.snapshot, at: now))
        }
        let oneLineVolatile = frames.first { frame in
            frame.lines.count == 1 && frame.lines[0].hasVolatileText && !frame.lines[0].finalText.isEmpty
        }
        let twoLinesVolatile = frames.first { frame in
            frame.lines.count == 2 && frame.lines.contains(where: \.hasVolatileText)
                && frame.lines.contains { line in !line.finalText.isEmpty }
        }
        let twoLinesFinal = frames.last { frame in
            frame.lines.count == 2 && !frame.lines.contains(where: \.hasVolatileText)
        }
        return [
            ("1-volatile-tail", oneLineVolatile),
            ("2-two-lines-volatile", twoLinesVolatile),
            ("3-final", twoLinesFinal),
        ].compactMap { name, frame in frame.map { (name, $0) } }
    }

    /// The overlay on a strip of fake desktop with a menu bar, at the size the
    /// panel would have.
    private static func scene(frame: CaptionFrame, style: OverlayStyle) -> some View {
        let caption = OverlayMetrics.captionSize(maxLines: CaptionComposer.Configuration.english.maxLines)
        let panelHeight = caption.height + style.topInset
        let menuBarHeight: CGFloat = 32
        let sceneWidth: CGFloat = 760
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom)
            Color(white: 0.85).frame(height: menuBarHeight)
            if case .notch(let notchWidth, let notchHeight) = style {
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black)
                    .frame(width: notchWidth, height: notchHeight)
            }
            CaptionOverlayView(frame: frame, style: style)
                .frame(width: caption.width, height: panelHeight)
                .padding(.top, style == .pill ? menuBarHeight + OverlayPlacement.pillGap : 0)
        }
        .frame(width: sceneWidth, height: max(panelHeight, menuBarHeight + OverlayPlacement.pillGap + caption.height) + 40)
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
