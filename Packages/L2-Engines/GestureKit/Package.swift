// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "GestureKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowGestureKit", targets: ["SuperflowGestureKit"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowGestureKit",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowGestureKitTests",
            dependencies: [
                "SuperflowGestureKit",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/GestureKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
