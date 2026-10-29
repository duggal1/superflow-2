// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TextLexicon",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextLexicon", targets: ["SuperflowTextLexicon"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowTextLexicon",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ], resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "SuperflowTextLexiconTests",
            dependencies: [
                "SuperflowTextLexicon",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/TextLexiconTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
