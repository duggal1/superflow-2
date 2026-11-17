// swift-tools-version: 6.4
import PackageDescription

/// Clearly input layer. Depends only on L0 so the gesture table and its tests
/// never pull in an engine, a feature, or a UI framework.
let package = Package(
    name: "ClearlyInput",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SuperflowClearlyInput", targets: ["SuperflowClearlyInput"]),
    ],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowClearlyInput",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowClearlyInputTests",
            dependencies: ["SuperflowClearlyInput"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
