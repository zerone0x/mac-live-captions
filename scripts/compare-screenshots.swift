// Compares rendered screenshots with the committed references (#23).
//
//   swift scripts/compare-screenshots.swift <reference dir> <actual dir>
//
// Every PNG in the reference directory must exist in the actual directory
// with the same pixel size. A pixel differs when any channel differs by more
// than `channelTolerance` (of 255); an image fails when more than
// `maxDifferingFraction` of its pixels differ. Failing images get a
// `<name>.diff.png` next to the actual image (differing pixels in red).
//
// Exit status: 0 all match, 1 a mismatch or a missing image, 2 usage or I/O error.
import AppKit
import CoreGraphics

let channelTolerance = 8
let maxDifferingFraction = 0.001

func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("compare-screenshots: \(message)\n".utf8))
    exit(status)
}

/// RGBA8 pixels of a PNG, drawn into a known format.
func pixels(of url: URL) -> (width: Int, height: Int, data: [UInt8])? {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width
    let height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (width, height, data) : nil
}

func writeDiff(width: Int, height: Int, mask: [Bool], to url: URL) {
    var data = [UInt8](repeating: 0, count: width * height * 4)
    for index in 0..<(width * height) {
        let value: [UInt8] = mask[index] ? [255, 0, 0, 255] : [255, 255, 255, 255]
        data.replaceSubrange(index * 4..<(index * 4 + 4), with: value)
    }
    guard
        let provider = CGDataProvider(data: Data(data) as CFData),
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fail("cannot encode \(url.path)") }
    do {
        try png.write(to: url)
    } catch {
        fail("cannot write \(url.path): \(error)")
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: compare-screenshots.swift <reference dir> <actual dir>") }
let referenceDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let actualDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

let references: [String]
do {
    references = try FileManager.default.contentsOfDirectory(atPath: referenceDirectory.path)
        .filter { $0.hasSuffix(".png") }
        .sorted()
} catch {
    fail("cannot list \(referenceDirectory.path): \(error)")
}
guard !references.isEmpty else { fail("no reference PNGs in \(referenceDirectory.path)") }

var mismatches = 0
for name in references {
    let actualURL = actualDirectory.appendingPathComponent(name)
    guard let reference = pixels(of: referenceDirectory.appendingPathComponent(name)) else {
        fail("cannot read reference \(name)")
    }
    guard FileManager.default.fileExists(atPath: actualURL.path) else {
        print("MISSING \(name)")
        mismatches += 1
        continue
    }
    guard let actual = pixels(of: actualURL) else { fail("cannot read \(actualURL.path)") }
    guard actual.width == reference.width, actual.height == reference.height else {
        print("SIZE    \(name): \(actual.width)x\(actual.height), reference \(reference.width)x\(reference.height)")
        mismatches += 1
        continue
    }
    let count = reference.width * reference.height
    var mask = [Bool](repeating: false, count: count)
    var differing = 0
    for index in 0..<count {
        for channel in 0..<4 {
            let offset = index * 4 + channel
            if abs(Int(actual.data[offset]) - Int(reference.data[offset])) > channelTolerance {
                mask[index] = true
                differing += 1
                break
            }
        }
    }
    let fraction = Double(differing) / Double(count)
    if fraction > maxDifferingFraction {
        let diffURL = actualDirectory.appendingPathComponent(name.replacingOccurrences(of: ".png", with: ".diff.png"))
        writeDiff(width: reference.width, height: reference.height, mask: mask, to: diffURL)
        print("DIFF    \(name): \(differing) of \(count) pixels differ, see \(diffURL.lastPathComponent)")
        mismatches += 1
    } else {
        print("ok      \(name) (\(differing) pixels differ)")
    }
}
if mismatches > 0 {
    fail("\(mismatches) of \(references.count) screenshots differ from the references", status: 1)
}
print("all \(references.count) screenshots match the references")
