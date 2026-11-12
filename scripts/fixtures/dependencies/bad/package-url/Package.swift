// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "X",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
    ],
    targets: [.target(name: "X")]
)
