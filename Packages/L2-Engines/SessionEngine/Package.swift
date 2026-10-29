// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionEngine",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowSessionEngine", targets: ["SuperflowSessionEngine"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
        .package(path: "../../L2-Engines/TextPipeline"),
        .package(path: "../../L2-Engines/AudioEnhancement"),
    ],
    targets: [
        .target(
            name: "SuperflowSessionEngine",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
                .product(name: "SuperflowAudioEnhancement", package: "AudioEnhancement"),
            ]
        ),
        .testTarget(
            name: "SuperflowSessionEngineTests",
            dependencies: [
                "SuperflowSessionEngine",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
                .product(name: "SuperflowAudioEnhancement", package: "AudioEnhancement"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/SessionEngineTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
