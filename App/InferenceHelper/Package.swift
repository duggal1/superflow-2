// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "InferenceHelper",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SuperflowInferenceHelperProtocol", targets: ["SuperflowInferenceHelperProtocol"]),
        .library(name: "SuperflowInferenceHelperCore", targets: ["SuperflowInferenceHelperCore"]),
        .executable(name: "SuperflowInferenceHelper", targets: ["SuperflowInferenceHelper"]),
    ],
    dependencies: [
        .package(path: "../../Packages/L0-Core/Kernel"),
        .package(path: "../../Packages/L1-Adapters/LLMLlamaCpp"),
    ],
    targets: [
        .target(name: "SuperflowInferenceHelperProtocol"),
        .target(
            name: "SuperflowInferenceHelperCore",
            dependencies: [
                "SuperflowInferenceHelperProtocol",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowLLMCore", package: "LLMLlamaCpp"),
                .product(name: "SuperflowLLMLlamaCpp", package: "LLMLlamaCpp"),
            ]
        ),
        .executableTarget(
            name: "SuperflowInferenceHelper",
            dependencies: ["SuperflowInferenceHelperCore", "SuperflowInferenceHelperProtocol"]
        ),
        .testTarget(
            name: "SuperflowInferenceHelperTests",
            dependencies: [
                "SuperflowInferenceHelperCore",
                "SuperflowInferenceHelperProtocol",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowLLMCore", package: "LLMLlamaCpp"),
                .product(name: "SuperflowLLMLlamaCpp", package: "LLMLlamaCpp"),
            ],
            path: "Tests/InferenceHelperTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
