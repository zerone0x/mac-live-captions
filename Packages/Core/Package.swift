// swift-tools-version: 6.2
import PackageDescription

// The Swift 6 language mode is set explicitly, not left to the tools
// version. Warnings fail the build, locally and in CI (docs/DECISIONS.md 0019).
let strictSwiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "Core",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "LiveCaptionsCore", targets: ["LiveCaptionsCore"]),
    ],
    targets: [
        .target(
            name: "LiveCaptionsCore",
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "LiveCaptionsCoreTests",
            dependencies: ["LiveCaptionsCore"],
            swiftSettings: strictSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
