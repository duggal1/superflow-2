// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemAudioCapture",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowSystemAudioCapture", targets: ["SuperflowSystemAudioCapture"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowSystemAudioCapture",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowSystemAudioCaptureTests",
            dependencies: [
                "SuperflowSystemAudioCapture",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/SystemAudioCaptureTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
