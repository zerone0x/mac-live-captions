// swift-tools-version: 6.2
import PackageDescription

// Platform adapter for on-device speech recognition (docs/DECISIONS.md, 0007).
// Wraps Apple's Speech framework behind the Core `Transcriber` and
// `SpeechAssetProvider` protocols. Logic that can be tested without the Speech
// framework stays in Core.
let package = Package(
    name: "SpeechAdapter",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "LiveCaptionsSpeech", targets: ["LiveCaptionsSpeech"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "LiveCaptionsSpeech",
            dependencies: [
                .product(name: "LiveCaptionsCore", package: "Core"),
            ]
        ),
        .testTarget(
            name: "LiveCaptionsSpeechTests",
            dependencies: [
                "LiveCaptionsSpeech",
                .product(name: "LiveCaptionsCore", package: "Core"),
            ]
        ),
    ]
)
