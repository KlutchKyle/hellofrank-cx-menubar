// swift-tools-version:5.9
import PackageDescription

// HelloFrankCore is Foundation-only (models, marker parsing, pipeline state,
// Linear/Slack clients, change detection) so it builds and tests anywhere.
// HelloFrankCX is the macOS menu bar app (SwiftUI, Keychain, notifications).
let package = Package(
    name: "HelloFrankCX",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HelloFrankCX", targets: ["HelloFrankCX"]),
        .library(name: "HelloFrankCore", targets: ["HelloFrankCore"]),
    ],
    targets: [
        .target(name: "HelloFrankCore"),
        .executableTarget(
            name: "HelloFrankCX",
            dependencies: ["HelloFrankCore"]
        ),
        .testTarget(
            name: "HelloFrankCoreTests",
            dependencies: ["HelloFrankCore"]
        ),
    ]
)
