// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ports",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowPorts", targets: ["SuperflowPorts"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
    ],
    targets: [
        .target(
            name: "SuperflowPorts",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
            ]
        ),
        .testTarget(
            name: "SuperflowPortsTests",
            dependencies: [
                "SuperflowPorts",
                .product(name: "SuperflowKernel", package: "Kernel"),
            ],
            path: "Tests/PortsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
