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
            path: "Sources/WarawaraPet"
        ),
        .testTarget(
            name: "WarawaraPetTests",
            dependencies: ["WarawaraPet"],
            path: "Tests/WarawaraPetTests"
        )
    ]
)
