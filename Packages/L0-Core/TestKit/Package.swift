// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TestKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTestKit", targets: ["SuperflowTestKit"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTestKit",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTestKitTests",
            dependencies: [
                "SuperflowTestKit",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TestKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
