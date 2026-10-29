import AppKit
import SuperflowDesignSystem
import SwiftUI
import XCTest
@testable import SuperflowUIComponents

@MainActor
final class PixelToggleRenderTests: XCTestCase {
    func testPixelTogglesRenderInBothAppearances() throws {
        _ = NSApplication.shared
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let view = VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Off"); Spacer(); AppToggle("Off", isOn: .constant(false)) }
                HStack { Text("On"); Spacer(); AppToggle("On", isOn: .constant(true)) }
                HStack { Text("Disabled"); Spacer(); AppToggle("Disabled", isOn: .constant(true), enabled: false) }
            }.padding(24).frame(width: 320).background(Tok.surface).environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            let size = CGSize(width: 320, height: 192)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 384,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
            if let directory = ProcessInfo.processInfo.environment["TOGGLE_SNAPSHOT_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("toggle-\(name).png"))
            }
            window.close()
        }
    }
}
