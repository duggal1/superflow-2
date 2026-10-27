// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HotkeyEngine",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowHotkeyEngine", targets: ["SuperflowHotkeyEngine"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowHotkeyEngine",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowHotkeyEngineTests",
            dependencies: [
                "SuperflowHotkeyEngine",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/HotkeyEngineTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
