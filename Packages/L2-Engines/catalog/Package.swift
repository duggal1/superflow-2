// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TechDictionary",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowTechDictionary", targets: ["SuperflowTechDictionary"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
    ],
    targets: [
        .target(
            name: "SuperflowTechDictionary",
            dependencies: [.product(name: "SuperflowKernel", package: "Kernel")],
            path: ".",
            exclude: ["Package.swift"],
            sources: ["TechDictionary.swift", "AIEraLexicon.swift"],
            resources: [.copy("vocab_v4.json"), .copy("ai-era-lexicon.json")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
