// swift-tools-version: 6.4
import PackageDescription
let root = "../../../Packages"
let package = Package(name: "Replay", platforms: [.macOS(.v15)], dependencies: [
    .package(path: root + "/L0-Core/Kernel"),
    .package(path: root + "/L0-Core/Ports"),
    .package(path: root + "/L1-Adapters/LLMLlamaCpp"),
    .package(path: root + "/L2-Engines/TextCleanup"),
    .package(path: root + "/L2-Engines/TextPipeline"),
    .package(path: root + "/L0-Core/TestKit"),
    .package(path: root + "/L1-Adapters/AudioCpp"),
    .package(path: root + "/L2-Engines/SessionEngine"),
], targets: [.executableTarget(name: "Replay", dependencies: [
    .product(name: "SuperflowKernel", package: "Kernel"),
    .product(name: "SuperflowPorts", package: "Ports"),
    .product(name: "SuperflowLLMCore", package: "LLMLlamaCpp"),
    .product(name: "SuperflowLLMLlamaCpp", package: "LLMLlamaCpp"),
    .product(name: "SuperflowTextCleanup", package: "TextCleanup"),
    .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
    .product(name: "SuperflowTestKit", package: "TestKit"),
    .product(name: "SuperflowAudioCpp", package: "AudioCpp"),
    .product(name: "SuperflowSessionEngine", package: "SessionEngine"),
])], swiftLanguageModes: [.v6])
