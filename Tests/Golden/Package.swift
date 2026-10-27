// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuperflowGoldenTests",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/L0-Core/Kernel"),
        .package(path: "../../Packages/L0-Core/Ports"),
        .package(path: "../../Packages/L0-Core/TestKit"),
        .package(path: "../../Packages/L2-Engines/TextPipeline"),
        .package(path: "../../Packages/L2-Engines/TextNumbers"),
        .package(path: "../../Packages/L2-Engines/TextLexicon"),
        .package(path: "../../Packages/L2-Engines/TextShortcuts"),
        .package(path: "../../Packages/L2-Engines/TextLineFormat"),
        .package(path: "../../Packages/L2-Engines/TextCommands"),
        .package(path: "../../Packages/L2-Engines/TextGrammarGate"),
        .package(path: "../../Packages/L2-Engines/TextCleanup"),
        .package(path: "../../Packages/L2-Engines/MeetingEngine"),
    ],
    targets: [
        .testTarget(
            name: "SuperflowGoldenTests",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
                .product(name: "SuperflowTextNumbers", package: "TextNumbers"),
                .product(name: "SuperflowTextLexicon", package: "TextLexicon"),
                .product(name: "SuperflowTextShortcuts", package: "TextShortcuts"),
                .product(name: "SuperflowTextLineFormat", package: "TextLineFormat"),
                .product(name: "SuperflowTextCommands", package: "TextCommands"),
                .product(name: "SuperflowTextGrammarGate", package: "TextGrammarGate"),
                .product(name: "SuperflowTextCleanup", package: "TextCleanup"),
                .product(name: "SuperflowMeetingEngine", package: "MeetingEngine"),
            ],
            path: "Tests/GoldenTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
