// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AudioJournal",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowAudioJournal", targets: ["SuperflowAudioJournal"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: [
        .target(
            name: "SuperflowAudioJournal",
            dependencies: [
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ]
        ),
        .testTarget(
            name: "SuperflowAudioJournalTests",
            dependencies: [
                "SuperflowAudioJournal",
                .product(name: "SuperflowKernel", package: "Kernel"),
                .product(name: "SuperflowPorts", package: "Ports"),
            ],
            path: "Tests/AudioJournalTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
