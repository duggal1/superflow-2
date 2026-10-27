// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureShortcuts",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowFeatureShortcuts", targets: ["SuperflowFeatureShortcuts"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/TestKit"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L2-Engines/TextShortcuts"),
        .package(path: "../../L2-Engines/TextLexicon"),
        .package(path: "../../L4-UI/DesignSystem"),
        .package(path: "../../L4-UI/Icons"),
        .package(path: "../../L4-UI/UIComponents"),
    ],
    targets: [
        .target(
            name: "SuperflowFeatureShortcuts",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextShortcuts", package: "TextShortcuts"),
                .product(name: "SuperflowTextLexicon", package: "TextLexicon"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ]
        ),
        .testTarget(
            name: "SuperflowFeatureShortcutsTests",
            dependencies: [
                "SuperflowFeatureShortcuts",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextShortcuts", package: "TextShortcuts"),
                .product(name: "SuperflowTextLexicon", package: "TextLexicon"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ],
            path: "Tests/FeatureShortcutsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
