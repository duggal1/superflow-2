// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MeetingEngine",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowMeetingEngine", targets: ["SuperflowMeetingEngine"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
        .package(path: "../../L2-Engines/TextPipeline"),
        .package(path: "../../L2-Engines/AudioEnhancement"),
    ],
    targets: [
        .target(
            name: "SuperflowMeetingEngine",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
                .product(name: "SuperflowAudioEnhancement", package: "AudioEnhancement"),
            ]
        ),
        .testTarget(
            name: "SuperflowMeetingEngineTests",
            dependencies: [
                "SuperflowMeetingEngine",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
                .product(name: "SuperflowAudioEnhancement", package: "AudioEnhancement"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/MeetingEngineTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
