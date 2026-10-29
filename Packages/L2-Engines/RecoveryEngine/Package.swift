// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "RecoveryEngine",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowRecoveryEngine", targets: ["SuperflowRecoveryEngine"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
    ],
    targets: [
        .target(
            name: "SuperflowRecoveryEngine",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowRecoveryEngineTests",
            dependencies: [
                "SuperflowRecoveryEngine",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/RecoveryEngineTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
