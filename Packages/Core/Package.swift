// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "LiveCaptionsCore", targets: ["LiveCaptionsCore"]),
    ],
    targets: [
        .target(name: "LiveCaptionsCore"),
        .testTarget(
            name: "LiveCaptionsCoreTests",
            dependencies: ["LiveCaptionsCore"]
        ),
    ]
)
