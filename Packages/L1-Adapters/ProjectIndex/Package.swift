// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ProjectIndex",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowProjectIndex", targets: ["SuperflowProjectIndex"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
    ],
    targets: [
        .target(
            name: "SuperflowProjectIndex",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
            ]
        ),
        .testTarget(
            name: "SuperflowProjectIndexTests",
            dependencies: [
                "SuperflowProjectIndex",
                .product(name: "SuperflowKernel", package: "Kernel"),
            ],
            path: "Tests/ProjectIndexTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
