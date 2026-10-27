// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelStore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowModelStore", targets: ["SuperflowModelStore"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowModelStore",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SuperflowModelStoreTests",
            dependencies: [
                "SuperflowModelStore",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/ModelStoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
