// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kernel",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowKernel", targets: ["SuperflowKernel"])],
    dependencies: [
    ],
    targets: [
        .target(
            name: "SuperflowKernel",
            dependencies: [
            ]
        ),
        .testTarget(
            name: "SuperflowKernelTests",
            dependencies: [
                "SuperflowKernel",
            ],
            path: "Tests/KernelTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
