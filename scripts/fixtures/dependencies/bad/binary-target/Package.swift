// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "X",
    targets: [
        .binaryTarget(name: "Y", url: "https://example.com/Y.xcframework.zip", checksum: "abc"),
    ]
)
