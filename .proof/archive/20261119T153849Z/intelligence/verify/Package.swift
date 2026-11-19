// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "IntelligenceVerify",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../../Packages/L3-Features/FeatureIntelligence"),
        .package(path: "../../../Packages/L0-Core/Kernel"),
    ],
    targets: [
        .testTarget(
            name: "HeadlessIntelligenceTests",
            dependencies: [
                .product(name: "SuperflowFeatureIntelligence", package: "FeatureIntelligence"),
                .product(name: "SuperflowKernel", package: "Kernel"),
            ],
            
            sources: [
                "HeadlessIntelligenceFakes.swift",
                "HeadlessIntelligenceComposeTests.swift",
                "HeadlessIntelligenceHistoryTests.swift",
                "HeadlessIntelligencePromptTests.swift",
                "HeadlessIntelligenceUtteranceTests.swift",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
