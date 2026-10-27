// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureIsland",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowFeatureIsland", targets: ["SuperflowFeatureIsland"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L2-Engines/SessionEngine"),
        .package(path: "../../L2-Engines/MeetingEngine"),
        .package(path: "../../L4-UI/DesignSystem"),
        .package(path: "../../L4-UI/Icons"),
        .package(path: "../../L4-UI/UIComponents"),
    ],
    targets: [
        .target(
            name: "SuperflowFeatureIsland",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowSessionEngine", package: "SessionEngine"),
                .product(name: "SuperflowMeetingEngine", package: "MeetingEngine"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ]
        ),
        .testTarget(
            name: "SuperflowFeatureIslandTests",
            dependencies: [
                "SuperflowFeatureIsland",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowSessionEngine", package: "SessionEngine"),
                .product(name: "SuperflowMeetingEngine", package: "MeetingEngine"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ],
            path: "Tests/FeatureIslandTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
