// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureMeetings",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowFeatureMeetings", targets: ["SuperflowFeatureMeetings"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/TestKit"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L2-Engines/MeetingEngine"),
        .package(path: "../../L2-Engines/TextPipeline"),
        .package(path: "../../L4-UI/DesignSystem"),
        .package(path: "../../L4-UI/Icons"),
        .package(path: "../../L4-UI/UIComponents"),
    ],
    targets: [
        .target(
            name: "SuperflowFeatureMeetings",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowMeetingEngine", package: "MeetingEngine"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ]
        ),
        .testTarget(
            name: "SuperflowFeatureMeetingsTests",
            dependencies: [
                "SuperflowFeatureMeetings",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowMeetingEngine", package: "MeetingEngine"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
                .product(name: "SuperflowIcons", package: "Icons"),
                .product(name: "SuperflowUIComponents", package: "UIComponents"),
            ],
            path: "Tests/FeatureMeetingsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
