import AppKit
import SwiftUI
import XCTest
@testable import SuperflowFeatureIsland

private struct IdleLampFeed: IslandFeed {
    var events: AsyncStream<IslandEvent> { AsyncStream { $0.finish() } }
    var levels: AsyncStream<Float> { AsyncStream { $0.finish() } }
    var storesTranscripts: Bool { false }
    func lastTranscript() -> IslandTranscript? { nil }
}

@MainActor
final class IdleLampMotionTests: XCTestCase {
    func testAlwaysVisibleIdleLampAnimatesAndReduceMotionKeepsItStill() async throws {
        let moving = try await frames(reduceMotion: false)
        XCTAssertGreaterThan(Set(moving).count, 1, "The visible idle lamp should change over time")
        let external = try await frames(reduceMotion: false, notch: false)
        XCTAssertGreaterThan(Set(external).count, 1, "The external display lamp should change over time")
        let still = try await frames(reduceMotion: true)
        XCTAssertEqual(Set(still).count, 1, "Reduce Motion should keep the lamp stationary")
        XCTAssertFalse(try XCTUnwrap(still.first).isEmpty, "The stationary lamp should remain visible")
    }

    private func frames(reduceMotion: Bool, notch: Bool = true) async throws -> [[Int]] {
        _ = NSApplication.shared
        let geometry = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     safeTop: notch ? 32 : 0,
                                     leftWidth: notch ? 620 : nil, rightWidth: notch ? 620 : nil, scale: 2)
        let model = IslandModel(feed: IdleLampFeed(), geometry: geometry)
        model.configure(IslandPrefs(alwaysOn: true))
        let content: AnyView = reduceMotion
            ? AnyView(IdleLampView(reduceMotion: true).frame(width: IslandLayout.canvas.width,
                                                            height: IslandLayout.canvas.height, alignment: .top)
                .environment(\.colorScheme, .dark))
            : AnyView(IslandRoot(model: model))
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: IslandLayout.canvas),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))

        var results: [[Int]] = []
        for frame in 0..<5 {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(IslandLayout.canvas.width * 2), pixelsHigh: Int(IslandLayout.canvas.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = IslandLayout.canvas
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let output = ProcessInfo.processInfo.environment["IDLE_LAMP_SNAPSHOT_DIR"] {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let image = try XCTUnwrap(bitmap.cgImage?.cropping(to: CGRect(x: bitmap.pixelsWide / 2 - 50,
                                                                              y: 0, width: 100, height: 100)))
                let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let state = reduceMotion ? "still" : (notch ? "notch" : "external")
                try data.write(to: directory.appendingPathComponent("\(state)-\(frame).png"))
            }
            var lit: [Int] = []
            let center = bitmap.pixelsWide / 2
            for y in 0..<100 {
                for x in (center - 30)..<(center + 30) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.blueComponent > 0.8 && color.redComponent < 0.6 { lit.append(y * bitmap.pixelsWide + x) }
                }
            }
            results.append(lit)
            try await Task.sleep(for: .milliseconds(220))
        }
        return results
    }
}
