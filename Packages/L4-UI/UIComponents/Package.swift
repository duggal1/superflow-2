// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UIComponents",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowUIComponents", targets: ["SuperflowUIComponents"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L4-UI/DesignSystem"),
        .package(path: "../../L4-UI/Icons"),
    ],
    targets: [
        .target(
            name: "SuperflowUIComponents",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SuperflowUIComponentsTests",
            dependencies: [
                "SuperflowUIComponents",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
            ],
            path: "Tests/UIComponentsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
