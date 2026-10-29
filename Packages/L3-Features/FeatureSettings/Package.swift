// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FeatureSettings",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowFeatureSettings", targets: ["SuperflowFeatureSettings"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/TestKit"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L2-Engines/ContextProfiles"),
        .package(path: "../../L2-Engines/TextCodeSpeak"),
        .package(path: "../../L4-UI/DesignSystem"),
        .package(path: "../../L4-UI/Icons"),
        .package(path: "../../L4-UI/UIComponents"),
    ],
    targets: [
        .target(
            name: "SuperflowFeatureSettings",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowContextProfiles", package: "ContextProfiles"),
                .product(name: "SuperflowTextCodeSpeak", package: "TextCodeSpeak"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ]
        ),
        .testTarget(
            name: "SuperflowFeatureSettingsTests",
            dependencies: [
                "SuperflowFeatureSettings",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowContextProfiles", package: "ContextProfiles"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ],
            path: "Tests/FeatureSettingsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
