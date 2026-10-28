// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextDisfluency",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextDisfluency", targets: ["SuperflowTextDisfluency"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextDisfluency",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextDisfluencyTests",
            dependencies: [
                "SuperflowTextDisfluency",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextDisfluencyTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
