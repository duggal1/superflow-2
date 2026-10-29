// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TextLineFormat",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextLineFormat", targets: ["SuperflowTextLineFormat"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextLineFormat",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextLineFormatTests",
            dependencies: [
                "SuperflowTextLineFormat",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextLineFormatTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
