// Screen facts for scripts/live-screenshots.sh (#23). Run with `swift`.
//
//   swift scripts/screen-info.swift size          -> "<width> <height>" of the main screen in points
//   swift scripts/screen-info.swift windows <pid> -> one line per on-screen window of that process
//
// Window listing needs no Screen Recording permission for bounds and layer;
// titles are left out because they would need it.
import AppKit
import CoreGraphics

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("screen-info: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "size":
    guard let frame = NSScreen.main?.frame else { fail("no main screen") }
    print(Int(frame.width), Int(frame.height))
case "windows":
    guard arguments.count == 2, let pid = Int(arguments.last!) else { fail("usage: windows <pid>") }
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
default:
    fail("usage: size | windows <pid>")
}
