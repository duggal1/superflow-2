// swift-tools-version: 6.4
import PackageDescription
let root = "../../../Packages"
let package = Package(name: "Probe", platforms: [.macOS(.v15)], dependencies: [
    .package(path: root + "/L0-Core/Kernel"),
    .package(path: root + "/L0-Core/Ports"),
    .package(path: root + "/L1-Adapters/LLMLlamaCpp"),
    .package(path: root + "/L2-Engines/TextCleanup"),
    .package(path: root + "/L2-Engines/TextPipeline"),
], targets: [.executableTarget(name: "Probe", dependencies: [
    .product(name: "SuperflowKernel", package: "Kernel"),
    .product(name: "SuperflowPorts", package: "Ports"),
    .product(name: "SuperflowLLMCore", package: "LLMLlamaCpp"),
    .product(name: "SuperflowLLMLlamaCpp", package: "LLMLlamaCpp"),
    .product(name: "SuperflowTextCleanup", package: "TextCleanup"),
    .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
])], swiftLanguageModes: [.v6])
