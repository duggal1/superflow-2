// swift-tools-version: 6.0
import PackageDescription

/// Headless proof driver for the ClearlyInput fixed key bindings.
/// Links the REAL SuperflowClearlyInput module. Posts synthetic events only to
/// its OWN pid (never global), opens no GUI, moves no cursor.
let package = Package(
    name: "InputProof",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "/Users/harshitduggal/workspace/superflow/Packages/L1-Adapters/ClearlyInput"),
    ],
    targets: [
        .executableTarget(
            name: "InputProof",
            dependencies: [
                .product(name: "SuperflowClearlyInput", package: "ClearlyInput"),
            ]
        ),
    ]
)
