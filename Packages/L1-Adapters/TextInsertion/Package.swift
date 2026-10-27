// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextInsertion",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextInsertion", targets: ["SuperflowTextInsertion"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
    ],
    targets: [
        .target(
            name: "SuperflowTextInsertion",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextInsertionTests",
            dependencies: [
                "SuperflowTextInsertion",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/TextInsertionTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
