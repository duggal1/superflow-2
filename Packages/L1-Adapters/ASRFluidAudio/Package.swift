// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ASRFluidAudio",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowASRFluidAudio", targets: ["SuperflowASRFluidAudio"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .target(
            name: "SuperflowASRFluidAudio",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(
            name: "SuperflowASRFluidAudioTests",
            dependencies: [
                "SuperflowASRFluidAudio",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Tests/ASRFluidAudioTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
