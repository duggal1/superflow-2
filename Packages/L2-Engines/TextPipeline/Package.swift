// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TextPipeline",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTextPipeline", targets: ["SuperflowTextPipeline"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
        .package(path: "../../L2-Engines/TextCommands"),
        .package(path: "../../L2-Engines/TextShortcuts"),
        .package(path: "../../L2-Engines/TextNumbers"),
        .package(path: "../../L2-Engines/TextDisfluency"),
        .package(path: "../../L2-Engines/TextCodeSpeak"),
        .package(path: "../../L2-Engines/TextCodeAware"),
        .package(path: "../../L2-Engines/TextLexicon"),
        .package(path: "../../L2-Engines/TextCleanup"),
        .package(path: "../../L2-Engines/TextGrammarGate"),
        .package(path: "../../L2-Engines/TextLineFormat"),
    ],
    targets: [
        .target(
            name: "SuperflowTextPipeline",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextCommands", package: "TextCommands"),
                .product(name: "SuperflowTextShortcuts", package: "TextShortcuts"),
                .product(name: "SuperflowTextNumbers", package: "TextNumbers"),
                .product(name: "SuperflowTextDisfluency", package: "TextDisfluency"),
                .product(name: "SuperflowTextCodeSpeak", package: "TextCodeSpeak"),
                .product(name: "SuperflowTextCodeAware", package: "TextCodeAware"),
                .product(name: "SuperflowTextLexicon", package: "TextLexicon"),
                .product(name: "SuperflowTextCleanup", package: "TextCleanup"),
                .product(name: "SuperflowTextGrammarGate", package: "TextGrammarGate"),
                .product(name: "SuperflowTextLineFormat", package: "TextLineFormat"),
            ]
        ),
        .testTarget(
            name: "SuperflowTextPipelineTests",
            dependencies: [
                "SuperflowTextPipeline",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTextCommands", package: "TextCommands"),
                .product(name: "SuperflowTextShortcuts", package: "TextShortcuts"),
                .product(name: "SuperflowTextNumbers", package: "TextNumbers"),
                .product(name: "SuperflowTextDisfluency", package: "TextDisfluency"),
                .product(name: "SuperflowTextCodeSpeak", package: "TextCodeSpeak"),
                .product(name: "SuperflowTextCodeAware", package: "TextCodeAware"),
                .product(name: "SuperflowTextLexicon", package: "TextLexicon"),
                .product(name: "SuperflowTextCleanup", package: "TextCleanup"),
                .product(name: "SuperflowTextGrammarGate", package: "TextGrammarGate"),
                .product(name: "SuperflowTextLineFormat", package: "TextLineFormat"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/TextPipelineTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
