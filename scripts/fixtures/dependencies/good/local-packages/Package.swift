// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "X",
    // A comment may mention .package(url: "https://example.com") without failing.
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "X", dependencies: [.product(name: "Core", package: "Core")]),
    ]
)
