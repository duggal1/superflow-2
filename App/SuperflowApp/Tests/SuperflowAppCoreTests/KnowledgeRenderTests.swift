import AppKit
import SuperflowFeatureDictionary
import SuperflowFeatureShortcuts
import SuperflowKernel
import SuperflowStorageSQLite
import SuperflowTextPipeline
import SuperflowUIComponents
import SwiftUI
import XCTest
@testable import SuperflowAppCore

/// Headless render of the rebuilt knowledge surface and the fixed history page.
/// The window is parked far off screen and never activated, so the user sees
/// nothing. Screenshots are written to KNOWLEDGE_SNAPSHOT_DIR for visual review.
@MainActor
final class KnowledgeRenderTests: XCTestCase {
    func testKnowledgeAndHistoryRender() async throws {
        guard let output = ProcessInfo.processInfo.environment["KNOWLEDGE_SNAPSHOT_DIR"] else { return }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowledge-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("db.sqlite").path)
        let learning = DictionaryLearningEngine(learning: store, lexicon: store)
        let dictionary = DictionaryViewModel(repository: store)
        let shortcuts = ShortcutsViewModel(repository: store)
        await dictionary.load()
        await shortcuts.load()

        var learningEnabled = true
        var autoLearn = false
        let view = KnowledgeView(
            dictionary: dictionary, shortcuts: shortcuts, learning: learning,
            learningEnabled: Binding(get: { learningEnabled }, set: { learningEnabled = $0 }),
            autoLearnEnabled: Binding(get: { autoLearn }, set: { autoLearn = $0 }),
            onLearningChange: { })
            .environment(MenuHost())
            .environment(DialogHost())
            .environment(\.colorScheme, .dark)
            .frame(width: 960, height: 620)

        try render(view, name: "knowledge", output: output)
    }

    private func render(_ view: some View, name: String, output: String) throws {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let size = CGSize(width: 960, height: 620)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1920, pixelsHigh: 1240,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name)-dark.png"))
        window.close()
    }
}
