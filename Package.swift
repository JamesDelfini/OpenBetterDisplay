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
        .library(
            name: "OpenBetterDisplayUI",
            targets: ["OpenBetterDisplayUI"]
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
        .target(
            name: "OpenBetterDisplayUI",
            dependencies: ["OpenBetterDisplayCore"],
            path: "Sources/OpenBetterDisplayUI"
        ),
        .executableTarget(
            name: "OpenBetterDisplay",
            dependencies: ["OpenBetterDisplayCore", "OpenBetterDisplayUI"],
            path: "Sources/OpenBetterDisplay"
        ),
        .executableTarget(
            name: "PopoverPreview",
            dependencies: ["OpenBetterDisplayCore", "OpenBetterDisplayUI"],
            path: "Tools/PopoverPreview"
        ),
        .testTarget(
            name: "OpenBetterDisplayTests",
            dependencies: ["OpenBetterDisplayCore", "OpenBetterDisplayUI"],
            path: "Tests/OpenBetterDisplayTests"
        )
    ]
)
