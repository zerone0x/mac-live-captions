// swift-tools-version: 6.2
import PackageDescription

// The Swift 6 language mode is set explicitly, not left to the tools
// version. Warnings fail the build, locally and in CI (docs/DECISIONS.md 0019).
let strictSwiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

// Audio capture adapter code that can be tested without capture permissions
// (docs/DECISIONS.md, 0013): PCM buffer conversion with AVFoundation. The
// capture sources stay in the App target; their pure logic (status, run
// tokens, retries, silence) lives in Core.
let package = Package(
    name: "AudioAdapter",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "LiveCaptionsAudio", targets: ["LiveCaptionsAudio"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "LiveCaptionsAudio",
            dependencies: [
                .product(name: "LiveCaptionsCore", package: "Core"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "LiveCaptionsAudioTests",
            dependencies: [
                "LiveCaptionsAudio",
                .product(name: "LiveCaptionsCore", package: "Core"),
            ],
            swiftSettings: strictSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
