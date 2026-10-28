// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextCodeAware",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextCodeAware", targets: ["SuperflowTextCodeAware"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextCodeAware",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextCodeAwareTests",
            dependencies: [
                "SuperflowTextCodeAware",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextCodeAwareTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
