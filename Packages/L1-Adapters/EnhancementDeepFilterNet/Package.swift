// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnhancementDeepFilterNet",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SuperflowEnhancementDeepFilterNet", targets: ["SuperflowEnhancementDeepFilterNet"])
    ],
    dependencies: [
        .package(path: "../../L0-Core/Ports"),
        .package(url: "https://github.com/kylehowells/DeepFilterNet-mlx", branch: "master"),
    ],
    targets: [
        .target(
            name: "SuperflowEnhancementDeepFilterNet",
            dependencies: [
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "DeepFilterNetCoreML", package: "DeepFilterNet-mlx"),
            ]
        ),
        .testTarget(
            name: "SuperflowEnhancementDeepFilterNetTests",
            dependencies: ["SuperflowEnhancementDeepFilterNet"]
        ),
    ]
)
