// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeMenuCore"),
        .executableTarget(name: "ClaudeMenu", dependencies: ["ClaudeMenuCore"]),
        .testTarget(
            name: "ClaudeMenuCoreTests",
            dependencies: ["ClaudeMenuCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
