// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChatPulse",
    defaultLocalization: "ru",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ChatPulseCore", targets: ["ChatPulseCore"]),
        .executable(name: "ChatPulse", targets: ["ChatPulseApp"])
    ],
    targets: [
        .target(
            name: "ChatPulseCore",
            path: "Sources/ChatPulseCore"
        ),
        .executableTarget(
            name: "ChatPulseApp",
            dependencies: ["ChatPulseCore"],
            path: "Sources/ChatPulseApp"
        ),
        .testTarget(
            name: "ChatPulseCoreTests",
            dependencies: ["ChatPulseCore"],
            path: "Tests/ChatPulseCoreTests"
        )
    ]
)
