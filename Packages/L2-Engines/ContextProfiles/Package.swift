// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContextProfiles",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowContextProfiles", targets: ["SuperflowContextProfiles"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
    ],
    targets: [
        .target(
            name: "SuperflowContextProfiles",
            dependencies: [.product(name: "SuperflowKernel", package: "Kernel")]
        ),
        .testTarget(
            name: "SuperflowContextProfilesTests",
            dependencies: [
                "SuperflowContextProfiles",
                .product(name: "SuperflowKernel", package: "Kernel"),
            ],
            path: "Tests/ContextProfilesTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
