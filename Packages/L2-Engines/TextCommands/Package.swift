// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TextCommands",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextCommands", targets: ["SuperflowTextCommands"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextCommands",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextCommandsTests",
            dependencies: [
                "SuperflowTextCommands",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextCommandsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
