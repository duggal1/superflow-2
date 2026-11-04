// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "EnhancementDeepFilterNet",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SuperflowEnhancementDeepFilterNet", targets: ["SuperflowEnhancementDeepFilterNet"])
    ],
    dependencies: [
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/Kernel"),
        .package(url: "https://github.com/kylehowells/DeepFilterNet-mlx", revision: "c6c4b9dc98c62bfa90ed66c5fd4f5d54e88c7b4f"),
        // Match DeepFilterNet's lockfile: later MLX releases require Sendable captures.
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.30.6"),
    ],
    targets: [
        .target(
            name: "SuperflowEnhancementDeepFilterNet",
            dependencies: [
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "DeepFilterNetCoreML", package: "DeepFilterNet-mlx"),
            ]
        ),
        .testTarget(
            name: "SuperflowEnhancementDeepFilterNetTests",
            dependencies: ["SuperflowEnhancementDeepFilterNet"]
        ),
    ]
)
