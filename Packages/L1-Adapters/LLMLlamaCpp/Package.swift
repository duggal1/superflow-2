// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "LLMLlamaCpp",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SuperflowLLMCore", targets: ["SuperflowLLMCore"]),
        .library(name: "SuperflowLLMLlamaCpp", targets: ["SuperflowLLMLlamaCpp"]),
    ],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11556/llama-b11556-xcframework.zip",
            checksum: "d7b4cf441bd8958c7ffbb5a6ef82a3302cfd8a5d330f2ed081ecf69b6e2a0f41"
        ),
        .target(
            name: "SuperflowLLMCore",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "SuperflowLLMLlamaCpp",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                "SuperflowLLMCore",
                "llama",
            ]
        ),
        .testTarget(
            name: "SuperflowLLMLlamaCppTests",
            dependencies: [
                "SuperflowLLMCore",
                "SuperflowLLMLlamaCpp",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/LLMLlamaCppTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
