import AppKit
import SwiftUI
import SuperflowUIComponents
import XCTest
@testable import SuperflowAppCore

@MainActor
final class SystemStatusRenderTests: XCTestCase {
    func testSystemDialogRenders() throws {
        guard let directory = ProcessInfo.processInfo.environment["STATUS_SNAPSHOT_DIR"] else { return }
        _ = NSApplication.shared
        let view = SystemStatusDialog(status: "Ready", speech: "Nemotron 3.5 ASR Streaming 0.6B",
                                      cleanupEnabled: true, needsAttention: false, fix: {})
            .environment(DialogHost()).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let size = CGSize(width: 480, height: 260)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 520,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("system.png"))
    }
}
