// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatsEngine",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowStatsEngine", targets: ["SuperflowStatsEngine"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
    ],
    targets: [
        .target(
            name: "SuperflowStatsEngine",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
            ]
        ),
        .testTarget(
            name: "SuperflowStatsEngineTests",
            dependencies: [
                "SuperflowStatsEngine",
                .product(name: "SuperflowKernel", package: "Kernel"),
            ],
            path: "Tests/StatsEngineTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
