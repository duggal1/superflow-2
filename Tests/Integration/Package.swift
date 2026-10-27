// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuperflowIntegrationTests",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/L0-Core/Kernel"),
        .package(path: "../../Packages/L0-Core/TestKit"),
        .package(path: "../../Packages/L1-Adapters/AudioJournal"),
        .package(path: "../../Packages/L1-Adapters/StorageSQLite"),
        .package(path: "../../Packages/L2-Engines/MeetingEngine"),
        .package(path: "../../Packages/L2-Engines/RecoveryEngine"),
        .package(path: "../../Packages/L2-Engines/TextPipeline"),
    ],
    targets: [
        .testTarget(
            name: "SuperflowIntegrationTests",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowTestKit", package: "TestKit"),
                .product(name: "SuperflowAudioJournal", package: "AudioJournal"),
                .product(name: "SuperflowStorageSQLite", package: "StorageSQLite"),
                .product(name: "SuperflowMeetingEngine", package: "MeetingEngine"),
                .product(name: "SuperflowRecoveryEngine", package: "RecoveryEngine"),
                .product(name: "SuperflowTextPipeline", package: "TextPipeline"),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
