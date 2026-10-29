// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AudioCapture",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowAudioCapture", targets: ["SuperflowAudioCapture"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowAudioCapture",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowAudioCaptureTests",
            dependencies: [
                "SuperflowAudioCapture",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/AudioCaptureTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
