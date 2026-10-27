// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Diagnostics",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowDiagnostics", targets: ["SuperflowDiagnostics"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowDiagnostics",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowDiagnosticsTests",
            dependencies: [
                "SuperflowDiagnostics",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/DiagnosticsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
