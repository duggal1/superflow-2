// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ASRSherpaOnnx",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowASRSherpaOnnx", targets: ["SuperflowASRSherpaOnnx"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(url: "https://github.com/k2-fsa/sherpa-onnx.git", exact: "2.0.1"),
    ],
    targets: [
        .target(
            name: "SuperflowASRSherpaOnnx",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "sherpa-onnx", package: "sherpa-onnx"),
            ]
        ),
        .testTarget(
            name: "SuperflowASRSherpaOnnxTests",
            dependencies: [
                "SuperflowASRSherpaOnnx",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/ASRSherpaOnnxTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
