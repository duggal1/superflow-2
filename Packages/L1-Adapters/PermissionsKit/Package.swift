// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "PermissionsKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowPermissionsKit", targets: ["SuperflowPermissionsKit"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowPermissionsKit",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowPermissionsKitTests",
            dependencies: [
                "SuperflowPermissionsKit",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/PermissionsKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
