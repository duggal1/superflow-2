// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ClearlyStealth",
    platforms: [.macOS(.v15)],
    products: [
        // Both modules ship: Core is pure/headless-testable, the adapter owns
        // the AppKit + ScreenCaptureKit edge. Consumers import either module.
        .library(name: "ClearlyStealth", targets: ["ClearlyStealthCore", "ClearlyStealth"]),
    ],
    targets: [
        // No AppKit / ScreenCaptureKit in this target. Every rule and decision
        // here is testable without a GUI, permission, or a capture device.
        .target(name: "ClearlyStealthCore"),
        .testTarget(
            name: "ClearlyStealthCoreTests",
            dependencies: ["ClearlyStealthCore"],
            path: "Tests/ClearlyStealthCoreTests"
        ),
        // AppKit + ScreenCaptureKit edge. SCScreenshotManager is macOS 14+.
        .target(
            name: "ClearlyStealth",
            dependencies: ["ClearlyStealthCore"]
        ),
        // Headless driver: runs the REAL SCK positive-control verifier once and
        // prints the honest status as JSON. `--force-capturable` proves the
        // verifier can return Failed. No GUI app is launched or activated.
        .executableTarget(
            name: "StealthVerifyDriver",
            dependencies: ["ClearlyStealth", "ClearlyStealthCore"],
            path: "Sources/StealthVerifyDriver"
        ),
        .testTarget(
            name: "ClearlyStealthTests",
            dependencies: ["ClearlyStealth", "ClearlyStealthCore"],
            path: "Tests/ClearlyStealthTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
