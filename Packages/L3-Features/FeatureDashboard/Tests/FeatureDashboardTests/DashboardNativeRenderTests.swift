import AppKit
import SwiftUI
import SuperflowKernel
import SuperflowTestKit
import SuperflowUIComponents
import XCTest
@testable import SuperflowFeatureDashboard

@MainActor
final class DashboardNativeRenderTests: XCTestCase {
    func testDashboardWithRecentDictationRendersInBothAppearances() async throws {
        guard let output = ProcessInfo.processInfo.environment["DASHBOARD_SNAPSHOT_DIR"] else { return }
        let repository = InMemoryRepository()
        let record = SessionRecord(kind: .dictation, startedAt: Date(), status: .complete,
                                   frontmostBundleID: "com.apple.TextEdit", modelProfile: "test", wordCount: 14)
        try await repository.createSession(record)
        try await repository.appendSegment(Segment(sessionID: record.id, index: 0,
            startMs: 0, endMs: 5000, source: .mic,
            rawText: "um the budget is twelve thousand dollars",
            cleanedText: "The budget is $12,000, and we meet on Tuesday at 3 PM.", cleanupState: .cleaned))
        let model = DashboardViewModel(repository: repository)
        await model.load()
        XCTAssertEqual(model.recent.entries.count, 1)
        XCTAssertEqual(model.usage.count, 1)
        try await render(model, output: output)
    }

    private func render(_ model: DashboardViewModel, output: String) async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let host = NSHostingView(rootView: DashboardView(model: model)
                .environment(MenuHost()).environment(DialogHost())
                .environment(\.colorScheme, scheme).transaction { $0.disablesAnimations = true })
            host.sizingOptions = []
            let size = CGSize(width: 1040, height: 1240)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            try await Task.sleep(for: .seconds(1))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: 2080, pixelsHigh: 2480, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("dashboard-\(name).png"))
            window.close()
        }
    }
}
