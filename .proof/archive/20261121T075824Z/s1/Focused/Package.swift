// swift-tools-version: 6.4
import PackageDescription

let root = "../../../Packages"
let package = Package(name: "Focused", platforms: [.macOS(.v15)], dependencies: [
    .package(path: root + "/L0-Core/Kernel"),
    .package(path: root + "/L0-Core/Ports"),
    .package(path: root + "/L0-Core/TestKit"),
    .package(path: root + "/L2-Engines/TextPipeline"),
    .package(path: root + "/L2-Engines/TextCleanup"),
    .package(path: root + "/L2-Engines/TextLexicon"),
    .package(path: root + "/L2-Engines/TextGrammarGate"),
    .package(path: root + "/L2-Engines/TextLineFormat"),
    .package(path: root + "/L2-Engines/catalog"),
], targets: [.testTarget(name: "FocusedTests", dependencies: [
    .product(name: "SuperflowKernel", package: "Kernel"),
    .product(name: "SuperflowPorts", package: "Ports"),
    .product(name: "SuperflowTestKit", package: "TestKit"),
    .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
    .product(name: "SuperflowTextCleanup", package: "TextCleanup"),
    .product(name: "SuperflowTextLexicon", package: "TextLexicon"),
    .product(name: "SuperflowTextGrammarGate", package: "TextGrammarGate"),
    .product(name: "SuperflowTextLineFormat", package: "TextLineFormat"),
    .product(name: "SuperflowTechDictionary", package: "catalog"),
])], swiftLanguageModes: [.v6])
