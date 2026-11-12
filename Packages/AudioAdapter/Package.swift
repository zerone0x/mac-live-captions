// swift-tools-version: 6.2
import PackageDescription

// Audio capture adapter code that can be tested without capture permissions
// (docs/DECISIONS.md, 0012): PCM buffer conversion with AVFoundation. The
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
            ]
        ),
        .testTarget(
            name: "LiveCaptionsAudioTests",
            dependencies: [
                "LiveCaptionsAudio",
                .product(name: "LiveCaptionsCore", package: "Core"),
            ]
        ),
    ]
)
