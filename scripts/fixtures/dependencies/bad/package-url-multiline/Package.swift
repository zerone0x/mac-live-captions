// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "X",
    dependencies: [
        .package(
            url: "git@github.com:apple/swift-nio.git",
            exact: "2.0.0"
        ),
    ],
    targets: [.target(name: "X")]
)
