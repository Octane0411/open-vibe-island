// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgentDeck",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AgentDeckCore",
            targets: ["AgentDeckCore"]
        ),
        .executable(
            name: "AgentDeckHooks",
            targets: ["AgentDeckHooks"]
        ),
        .executable(
            name: "AgentDeckSetup",
            targets: ["AgentDeckSetup"]
        ),
        .executable(
            name: "AgentDeckApp",
            targets: ["AgentDeckApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "AgentDeckCore"
        ),
        .executableTarget(
            name: "AgentDeckHooks",
            dependencies: ["AgentDeckCore"]
        ),
        .executableTarget(
            name: "AgentDeckSetup",
            dependencies: ["AgentDeckCore"]
        ),
        .executableTarget(
            name: "AgentDeckApp",
            dependencies: [
                "AgentDeckCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AgentDeckCoreTests",
            dependencies: ["AgentDeckCore"]
        ),
        .testTarget(
            name: "AgentDeckAppTests",
            dependencies: ["AgentDeckApp", "AgentDeckCore"]
        ),
    ]
)
