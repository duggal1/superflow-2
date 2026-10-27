// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Icons",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowIcons", targets: ["SuperflowIcons"])],
    dependencies: [
        .package(path: "../../L4-UI/DesignSystem"),
    ],
    targets: [
        .target(
            name: "SuperflowIcons",
            dependencies: [
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SuperflowIconsTests",
            dependencies: [
                "SuperflowIcons",
                .product(name: "SuperflowDesignSystem", package: "DesignSystem"),
            ],
            path: "Tests/IconsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
