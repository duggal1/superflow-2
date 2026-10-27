// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextNumbers",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextNumbers", targets: ["SuperflowTextNumbers"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextNumbers",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextNumbersTests",
            dependencies: [
                "SuperflowTextNumbers",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextNumbersTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
