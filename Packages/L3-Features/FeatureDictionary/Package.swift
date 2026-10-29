// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FeatureDictionary",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowFeatureDictionary", targets: ["SuperflowFeatureDictionary"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/TestKit"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L2-Engines/TextLexicon"),
        .package(path: "../../L4-UI/DesignSystem"),
        .package(path: "../../L4-UI/Icons"),
        .package(path: "../../L4-UI/UIComponents"),
    ],
    targets: [
        .target(
            name: "SuperflowFeatureDictionary",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextLexicon", package: "TextLexicon"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ]
        ),
        .testTarget(
            name: "SuperflowFeatureDictionaryTests",
            dependencies: [
                "SuperflowFeatureDictionary",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ],
            path: "Tests/FeatureDictionaryTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
