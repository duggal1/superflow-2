// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextGrammarGate",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextGrammarGate", targets: ["SuperflowTextGrammarGate"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
    ],
    targets: [
        .target(
            name: "SuperflowTextGrammarGate",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ], resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "SuperflowTextGrammarGateTests",
            dependencies: [
                "SuperflowTextGrammarGate",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/TextGrammarGateTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
