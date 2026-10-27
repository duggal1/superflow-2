// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Superflowctl",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "superflowctl", targets: ["Superflowctl"])],
    dependencies: [
        .package(path: "../../Packages/L0-Core/Kernel"),
        .package(path: "../../Packages/L0-Core/Ports"),
        .package(path: "../../Packages/L1-Adapters/ASRFluidAudio"),
        .package(path: "../../Packages/L1-Adapters/AudioCapture"),
        .package(path: "../../Packages/L1-Adapters/AudioJournal"),
        .package(path: "../../Packages/L2-Engines/TextPipeline"),
    ],
    targets: [
        .executableTarget(
            name: "Superflowctl",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowASRFluidAudio", package: "ASRFluidAudio"),
                .product(name: "SuperflowAudioCapture", package: "AudioCapture"),
                .product(name: "SuperflowAudioJournal", package: "AudioJournal"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
