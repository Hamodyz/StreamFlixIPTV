// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StreamFlixCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "StreamFlixCore",
            targets: ["StreamFlixCore"]
        )
    ],
    targets: [
        .target(
            name: "StreamFlixCore",
            path: "Sources/StreamFlixCore"
        ),
        .testTarget(
            name: "StreamFlixCoreTests",
            dependencies: ["StreamFlixCore"],
            path: "Tests/StreamFlixCoreTests"
        )
    ]
)
