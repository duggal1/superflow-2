// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TextShortcuts",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextShortcuts", targets: ["SuperflowTextShortcuts"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextShortcuts",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextShortcutsTests",
            dependencies: [
                "SuperflowTextShortcuts",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextShortcutsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
