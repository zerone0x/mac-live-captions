// Screen facts for scripts/live-screenshots.sh (#23, #38). Run with `swift`.
//
//   swift scripts/screen-info.swift size          -> "<width> <height>" of the main screen in points
//   swift scripts/screen-info.swift windows <pid> -> one line per on-screen window of that process
//   swift scripts/screen-info.swift overlay-check <png> <screen width> <x> <y> <width> <height>
//       -> whether the window at that frame (points, top-left origin, as `windows` prints it)
//          is in the screenshot, or the capture shows only the desktop there
//
// Window listing needs no Screen Recording permission for bounds and layer;
// titles are left out because they would need it. Without Screen Recording,
// `screencapture` still succeeds but leaves other apps' windows out, so only
// the pixels can tell (overlay-check).
//
// Exit status: 0 ok, 1 overlay-check found only the desktop, 2 usage or I/O
// error, or a desktop around the frame too busy to tell.
import AppKit
import CoreGraphics

func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("screen-info: \(message)\n".utf8))
    exit(status)
}

/// A channel differs from the desktop colour by more than this (of 255).
let colourTolerance = 40
/// The desktop around the frame must be this uniform to tell it apart.
let minUniformFraction = 0.9
/// This share of the inner frame must differ from the desktop.
let minShownFraction = 0.5

/// RGBA8 pixels of a PNG, top row first.
func pixels(of url: URL) -> (width: Int, height: Int, data: [UInt8])? {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width
    let height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
        guard
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (width, height, data) : nil
}

func overlayCheck(_ arguments: [String]) -> Never {
    let usage = "usage: overlay-check <png> <screen width> <x> <y> <width> <height>"
    guard arguments.count == 6 else { fail(usage) }
    let numbers = arguments.dropFirst().compactMap { Double($0) }
    guard numbers.count == 5, numbers[0] > 0, numbers[3] > 0, numbers[4] > 0 else { fail(usage) }
    guard let image = pixels(of: URL(fileURLWithPath: arguments[0])) else { fail("cannot read \(arguments[0])") }
    // Points to pixels: a Retina capture has twice the screen's points.
    let scale = Double(image.width) / numbers[0]
    let frame = CGRect(x: numbers[1], y: numbers[2], width: numbers[3], height: numbers[4])

    /// Pixels whose centre lies in `rect` (points), clipped to the image.
    func samples(in rect: CGRect) -> [[Int]] {
        let x0 = max(0, Int((rect.minX * scale).rounded()))
        let x1 = min(image.width, Int((rect.maxX * scale).rounded()))
        let y0 = max(0, Int((rect.minY * scale).rounded()))
        let y1 = min(image.height, Int((rect.maxY * scale).rounded()))
        guard x0 < x1, y0 < y1 else { return [] }
        var result: [[Int]] = []
        for y in y0..<y1 {
            for x in x0..<x1 {
                let offset = (y * image.width + x) * 4
                result.append([Int(image.data[offset]), Int(image.data[offset + 1]), Int(image.data[offset + 2])])
            }
        }
        return result
    }

    // Inside: away from the rounded corners and the edge.
    let inner = frame.insetBy(dx: min(20, frame.width / 4), dy: min(4, frame.height / 4))
    // Desktop: bands left, right and below the frame, a little away from it
    // (its shadow). Not above: at the top of the screen that is the menu bar.
    let gap = 6.0
    let band = 10.0
    let tall = frame.height + gap + band
    var ring = samples(in: CGRect(x: frame.minX - gap - band, y: frame.minY, width: band, height: tall))
    ring += samples(in: CGRect(x: frame.maxX + gap, y: frame.minY, width: band, height: tall))
    ring += samples(in: CGRect(x: frame.minX, y: frame.maxY + gap, width: frame.width, height: band))
    let inside = samples(in: inner)
    guard ring.count >= 100, inside.count >= 100 else {
        fail("frame \(frame) is too small or off the \(image.width)x\(image.height) image (scale \(scale))")
    }

    let desktop = (0..<3).map { channel -> Int in
        let values = ring.map { $0[channel] }.sorted()
        return values[values.count / 2]
    }
    func differs(_ pixel: [Int]) -> Bool {
        (0..<3).contains { abs(pixel[$0] - desktop[$0]) > colourTolerance }
    }
    let uniform = Double(ring.filter { !differs($0) }.count) / Double(ring.count)
    let shown = Double(inside.filter(differs).count) / Double(inside.count)
    let around = "desktop colour \(desktop) (\(Int(uniform * 100))% of the pixels around the frame)"
    let summary = "\(around), \(Int(shown * 100))% of the frame differs from it"
    guard uniform >= minUniformFraction else {
        fail("the desktop around the frame is not one colour, so the check can't tell (\(summary))")
    }
    guard shown >= minShownFraction else {
        fail("the frame shows only the desktop: is Screen Recording denied? (\(summary))", status: 1)
    }
    print("window drawn: \(summary)")
    exit(0)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "size":
    guard let frame = NSScreen.main?.frame else { fail("no main screen") }
    print(Int(frame.width), Int(frame.height))
case "windows":
    guard arguments.count == 2, let pid = Int(arguments[1]) else { fail("usage: windows <pid>") }
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        fail("CGWindowListCopyWindowInfo failed")
    }
    for window in list where (window[kCGWindowOwnerPID as String] as? Int) == pid {
        let layer = window[kCGWindowLayer as String] as? Int ?? -1
        let alpha = window[kCGWindowAlpha as String] as? Double ?? -1
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let x = bounds["X"] as? Double ?? -1
        let y = bounds["Y"] as? Double ?? -1
        let width = bounds["Width"] as? Double ?? -1
        let height = bounds["Height"] as? Double ?? -1
        print("layer=\(layer) alpha=\(alpha) x=\(Int(x)) y=\(Int(y)) width=\(Int(width)) height=\(Int(height))")
    }
case "overlay-check":
    overlayCheck(Array(arguments.dropFirst()))
default:
    fail("usage: size | windows <pid> | overlay-check <png> <screen width> <x> <y> <width> <height>")
}
