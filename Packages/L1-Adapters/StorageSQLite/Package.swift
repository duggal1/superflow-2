// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "StorageSQLite",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowStorageSQLite", targets: ["SuperflowStorageSQLite"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
        .package(path: "../../L0-Core/TestKit"),
    ],
    targets: [
        .target(
            name: "SuperflowStorageSQLite",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "SuperflowStorageSQLiteTests",
            dependencies: [
                "SuperflowStorageSQLite",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
            ],
            path: "Tests/StorageSQLiteTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
