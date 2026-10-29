// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "AudioEnhancement", platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowAudioEnhancement", targets: ["SuperflowAudioEnhancement"])],
    dependencies: [.package(path: "../../L0-Core/Ports")],
    targets: [
        .target(name: "SuperflowAudioEnhancement", dependencies: [.product(name: "SuperflowPorts", package: "Ports")]),
        .testTarget(name: "AudioEnhancementTests", dependencies: ["SuperflowAudioEnhancement", .product(name: "SuperflowPorts", package: "Ports")]),
    ], swiftLanguageModes: [.v6]
)
