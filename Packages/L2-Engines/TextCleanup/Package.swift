// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TextCleanup",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextCleanup", targets: ["SuperflowTextCleanup"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
    ],
    targets: [
        .target(
            name: "SuperflowTextCleanup",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextCleanupTests",
            dependencies: [
                "SuperflowTextCleanup",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/TextCleanupTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
