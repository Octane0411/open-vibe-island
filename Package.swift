// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenIsland",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenIslandCore",
            targets: ["OpenIslandCore"]
        ),
        .executable(
            name: "OpenIslandHooks",
            targets: ["OpenIslandHooks"]
        ),
        .executable(
            name: "OpenIslandSetup",
            targets: ["OpenIslandSetup"]
        ),
        .executable(
            name: "OpenIslandApp",
            targets: ["OpenIslandApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        // Test-only (AB-327): deterministic theme-conformance snapshot goldens.
        // Linked only into the OpenIslandAppTests target below, so it never
        // ships in any product binary. `Package.resolved` is gitignored repo-wide,
        // so the pin lives here; validated against 1.19.3.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.3"),
    ],
    targets: [
        .target(
            name: "OpenIslandCore"
        ),
        .executableTarget(
            name: "OpenIslandHooks",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "OpenIslandSetup",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "OpenIslandApp",
            dependencies: [
                "OpenIslandCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OpenIslandCoreTests",
            dependencies: ["OpenIslandCore"]
        ),
        .testTarget(
            name: "OpenIslandAppTests",
            dependencies: [
                "OpenIslandApp",
                "OpenIslandCore",
                // AB-327: theme-conformance snapshot harness. Test-target-only —
                // no product links against it.
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
