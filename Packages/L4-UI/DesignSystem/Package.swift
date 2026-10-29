// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowDesignSystem", targets: ["SuperflowDesignSystem"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
    ],
    targets: [
        .target(
            name: "SuperflowDesignSystem",
            dependencies: [.product(name: "SuperflowKernel", package: "Kernel")]
        ),
        .testTarget(
            name: "SuperflowDesignSystemTests",
            dependencies: ["SuperflowDesignSystem"],
            path: "Tests/DesignSystemTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
