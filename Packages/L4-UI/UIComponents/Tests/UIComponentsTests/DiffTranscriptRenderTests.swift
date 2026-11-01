import AppKit
import SuperflowDesignSystem
import SwiftUI
import XCTest
@testable import SuperflowUIComponents

@MainActor
private final class DiffRenderState: ObservableObject {
    @Published var raw = false
}

private struct DiffRenderView: View {
    @ObservedObject var state: DiffRenderState
    var body: some View {
        DiffTranscript(raw: "um the budget is twelve thousand dollars",
                       cleaned: "The budget is $12,000.", showRaw: $state.raw)
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Tok.bg)
    }
}

@MainActor
final class DiffTranscriptRenderTests: XCTestCase {
    func testComparisonRendersHighlightsInBothModesAndAppearances() async throws {
        _ = NSApplication.shared
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let state = DiffRenderState()
            let host = NSHostingView(rootView: DiffRenderView(state: state).environment(\.colorScheme, scheme))
            host.sizingOptions = []
            let size = CGSize(width: 720, height: 240)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            for showRaw in [false, true] {
                state.raw = showRaw
                try await Task.sleep(for: .milliseconds(700))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                bitmap.size = size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                var bluePixels = 0
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        if color.blueComponent > color.redComponent + 0.15 { bluePixels += 1 }
                    }
                }
                XCTAssertGreaterThan(bluePixels, 100, "\(name) \(showRaw ? "raw" : "cleaned") should show highlights")
                if let output = ProcessInfo.processInfo.environment["DIFF_SNAPSHOT_DIR"] {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(name)-\(showRaw ? "raw" : "cleaned").png"))
                }
            }
        }
    }
}
