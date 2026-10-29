// swift-tools-version: 6.4
import Foundation
import PackageDescription

// The real backend is the XCFramework built by `make harper`. When it is absent
// (or when SUPERFLOW_HARPER_FFI=0 forces the deterministic path) the package
// compiles a C stub with the same ABI, so `swift build` and `swift test` work
// everywhere. The stub reports itself through `harper_linter_is_stub()`.
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let frameworkPath = packageDirectory
    .appendingPathComponent("../../../Rust/harper-ffi/HarperFFI.xcframework")
    .standardizedFileURL.path
let forceStub = ProcessInfo.processInfo.environment["SUPERFLOW_HARPER_FFI"] == "0"
let hasRealHarper = FileManager.default.fileExists(atPath: frameworkPath) && !forceStub

var targets: [Target] = []
if hasRealHarper {
    targets.append(.binaryTarget(name: "HarperFFI", path: "../../../Rust/harper-ffi/HarperFFI.xcframework"))
} else {
    targets.append(.target(name: "HarperFFI",
                           path: "Sources/HarperFFIStub",
                           publicHeadersPath: "include"))
}
targets.append(.target(
    name: "SuperflowGrammarHarper",
    dependencies: [
        .product(name: "SuperflowKernel", package: "Kernel"),
        .product(name: "SuperflowPorts", package: "Ports"),
        "HarperFFI",
    ]
))
targets.append(.testTarget(
    name: "SuperflowGrammarHarperTests",
    dependencies: [
        "SuperflowGrammarHarper",
        .product(name: "SuperflowKernel", package: "Kernel"),
        .product(name: "SuperflowPorts", package: "Ports"),
    ],
    path: "Tests/GrammarHarperTests"
))

let package = Package(
    name: "GrammarHarper",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowGrammarHarper", targets: ["SuperflowGrammarHarper"])],
    dependencies: [
        .package(path: "../../L0-Core/Kernel"),
        .package(path: "../../L0-Core/Ports"),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
