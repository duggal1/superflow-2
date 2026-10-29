// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TextCodeSpeak",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextCodeSpeak", targets: ["SuperflowTextCodeSpeak"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextCodeSpeak",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextCodeSpeakTests",
            dependencies: [
                "SuperflowTextCodeSpeak",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextCodeSpeakTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
