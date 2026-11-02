// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MeetingIntelligence",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SuperflowMeetingIntelligence", targets: ["SuperflowMeetingIntelligence"])],
    targets: [
        .target(name: "SuperflowMeetingIntelligence"),
        .testTarget(name: "MeetingIntelligenceTests", dependencies: ["SuperflowMeetingIntelligence"]),
    ],
    swiftLanguageModes: [.v6]
)
