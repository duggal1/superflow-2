import AppKit
import CoreText
import SuperflowKernel
import SuperflowTestKit
import SuperflowUIComponents
import SwiftUI
import XCTest
@testable import SuperflowFeatureSettings

@MainActor
final class SettingsRenderTests: XCTestCase {
    func testSettingsTabsRender() async throws {
        guard let output = ProcessInfo.processInfo.environment["SETTINGS_SNAPSHOT_DIR"] else { return }
        _ = NSApplication.shared
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        for name in ["SerifVinci.otf", "InstrumentSans-Variable.ttf"] {
            _ = CTFontManagerRegisterFontsForURL(root.appendingPathComponent("App/Resources/Fonts/\(name)") as CFURL, .process, nil)
        }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        for tab in SettingsTab.allCases {
            let model = SettingsViewModel(store: InMemorySettings(.default), launchAtLogin: FakeLaunchAtLogin())
            await model.load()
            let view = SettingsView(model: model, initialTab: tab)
                .environment(MenuHost()).environment(DialogHost()).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            let size = CGSize(width: 740, height: 620)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1480, pixelsHigh: 1240,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: output).appendingPathComponent("settings-\(tab.rawValue).png"))
            if tab == .privacy, let scroll = findScrollView(host), let document = scroll.documentView {
                let offset = max(0, document.bounds.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: CGPoint(x: 0, y: document.isFlipped ? offset : 0))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await Task.sleep(for: .milliseconds(200))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: output).appendingPathComponent("settings-privacy-scrolled.png"))
            }
            window.close()
        }
    }

    private func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView($0) }.first
    }
}
