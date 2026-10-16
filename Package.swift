// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WarawaraPet",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "WarawaraPet",
            path: "Sources/WarawaraPet",
            resources: [
                .process("Resources/Sprites"),
                // Rig resources are copied verbatim so the declared layer
                // paths (body/, eyes/, mouth/) survive packaging.
                .copy("Resources/Assets"),
                // Birthday props + letter text (UTF-8, never baked into
                // artwork).
                .copy("Resources/Birthday"),
                // Seasonal + daily event props (Phase 6B).
                .copy("Resources/Seasonal")
            ]
        ),
        .testTarget(
            name: "WarawaraPetTests",
            dependencies: ["WarawaraPet"],
            path: "Tests/WarawaraPetTests"
        )
    ]
)
