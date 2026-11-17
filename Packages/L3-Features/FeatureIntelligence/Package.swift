// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FeatureIntelligence",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowFeatureIntelligence", targets: ["SuperflowFeatureIntelligence"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L2-Engines/MeetingIntelligence"),
        .package(path: "../../L4-UI/DesignSystem"),
        .package(path: "../../L4-UI/Icons"),
        .package(path: "../../L4-UI/UIComponents"),
    ],
    targets: [
        .target(
            name: "SuperflowFeatureIntelligence",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowMeetingIntelligence", package: "MeetingIntelligence"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ]
        ),
        .testTarget(
            name: "FeatureIntelligenceTests",
            dependencies: [
                "SuperflowFeatureIntelligence",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowMeetingIntelligence", package: "MeetingIntelligence"),
            ],
            path: "Tests/FeatureIntelligenceTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
