// swift-tools-version: 6.4
import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../..", isDirectory: true).standardizedFileURL
let native = root.appendingPathComponent("ThirdParty/audio.cpp/build/superflow-metal")
let package = Package(
    name: "AudioCpp",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowAudioCpp", targets: ["SuperflowAudioCpp"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .systemLibrary(name: "CAudioCpp"),
        .target(name: "SuperflowAudioCpp", dependencies: [
            "CAudioCpp",
            .product(name: "SuperflowKernel", package: "Kernel"),
            .product(name: "SuperflowPorts", package: "Ports"),
        ], linkerSettings: [.unsafeFlags([
            "-L", native.appendingPathComponent("bin").path,
            "-Xlinker", "-rpath", "-Xlinker", native.appendingPathComponent("bin").path,
        ])]),
        .testTarget(name: "AudioCppTests", dependencies: ["SuperflowAudioCpp"], path: "Tests"),
    ],
    swiftLanguageModes: [.v6]
)
