// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenBetterDisplay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OpenBetterDisplayCore",
            targets: ["OpenBetterDisplayCore"]
        ),
        .executable(
            name: "OpenBetterDisplay",
            targets: ["OpenBetterDisplay"]
        )
    ],
    targets: [
        .target(
            name: "OpenBetterDisplayCore",
            path: "Sources/OpenBetterDisplayCore"
        ),
        .executableTarget(
            name: "OpenBetterDisplay",
            dependencies: ["OpenBetterDisplayCore"],
            path: "Sources/OpenBetterDisplay"
        ),
        .testTarget(
            name: "OpenBetterDisplayTests",
            dependencies: ["OpenBetterDisplayCore"],
            path: "Tests/OpenBetterDisplayTests"
        )
    ]
)
