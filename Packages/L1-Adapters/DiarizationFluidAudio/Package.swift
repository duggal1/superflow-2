// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiarizationFluidAudio",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowDiarizationFluidAudio", targets: ["SuperflowDiarizationFluidAudio"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .target(
            name: "SuperflowDiarizationFluidAudio",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(
            name: "SuperflowDiarizationFluidAudioTests",
            dependencies: [
                "SuperflowDiarizationFluidAudio",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Tests/DiarizationFluidAudioTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
