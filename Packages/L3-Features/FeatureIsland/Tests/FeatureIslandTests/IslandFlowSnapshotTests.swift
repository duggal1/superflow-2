import AppKit
import SuperflowDesignSystem
import SwiftUI
import XCTest
@testable import SuperflowFeatureIsland

/// Headless render of every rebuilt state. Assertions are structural (the flat
/// top row is painted, the bottom stays inside the silhouette box, the body is
/// opaque black) so they do not depend on a golden font raster. Images are
/// written to `ISLAND_SNAPSHOT_DIR` for a human to look at, never opened on screen.
@MainActor
final class IslandFlowSnapshotTests: XCTestCase {
    private let geometry = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                         safeTop: 32, leftWidth: 620, rightWidth: 620, scale: 2)

    private var states: [(String, IslandFlowState)] {
        [
            ("collapsed", .collapsed),
            ("compose", .compose(draft: "")),
            ("listening", .listening(target: "TextEdit")),
            ("thinking", .thinking(query: "what did we decide?")),
            ("answer", .answer(text: "We decided to ship on Tuesday.", streaming: false)),
            ("streaming", .answer(text: "We decided…", streaming: true)),
            ("meeting-live", .meetingLive(elapsed: 252)),
            ("meeting-ended", .meetingEnded(suggestions: ["What next?", "Any risks?"])),
            ("undo", .undo(text: String(repeating: "A long cancelled transcript ", count: 8))),
            ("history", .history(count: 5)),
            ("settings", .settings(theme: IslandTokens.Theme.journal.rawValue)),
            ("error", .error(message: "The answer could not be completed.")),
            ("permission", .permission(kind: .microphone)),
        ]
    }

    private func context(_ state: IslandFlowState) -> FlowContext {
        var ctx = FlowContext()
        ctx.meter = IslandMeterModel()
        ctx.live = "the newest words stay beside the caret"
        ctx.target = "TextEdit"
        ctx.history = (0..<3).map { i in
            IslandTranscript(text: "Transcript number \(i) with a sentence long enough to read.",
                             bundleID: nil, appName: nil, date: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                             words: 10 + i)
        }
        if case .meetingEnded(let suggestions) = state {
            ctx.intelligence = IslandIntelligenceContent(suggestions: suggestions)
        }
        return ctx
    }

    private func box(for state: IslandFlowState) -> IslandBox {
        let showsLive = if case .listening = state { true } else { false }
        return IslandFlowMetrics.box(state, notchWidth: geometry.notch.width,
                                     band: geometry.band, hasNotch: true, liveText: showsLive)
    }

    /// Renders through an offscreen `NSHostingView`. `ImageRenderer` cannot draw
    /// AppKit-backed controls (a TextField becomes a yellow "no" placeholder),
    /// so it cannot be trusted for these snapshots. The window is parked far off
    /// screen and never activated: nothing appears on the user's display.
    private func render(_ state: IslandFlowState, scheme: ColorScheme, reduce: Bool) throws -> NSImage {
        let box = box(for: state)
        let view = IslandShell(box: box, stageID: state.stageID, clickable: false,
                               clickLabel: "x", onHover: { _ in }, onClick: {}, hitRect: { _ in }) { _ in
            FlowContent(state: state, context: self.context(state))
        }
        .frame(width: IslandTokens.Size.canvas.width, height: IslandTokens.Size.canvas.height, alignment: .top)
        .environment(\.appTypeScope, .island)
        .environment(\.colorScheme, scheme)
        .islandReduceMotion(reduce)

        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        })
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000),
                                                  size: IslandTokens.Size.canvas),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(IslandTokens.Size.canvas.width * 2),
            pixelsHigh: Int(IslandTokens.Size.canvas.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = IslandTokens.Size.canvas
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: IslandTokens.Size.canvas)
    }

    // MARK: every state

    func testEveryStateRendersAtTwoTimesScale() throws {
        for (name, state) in states {
            let image = try render(state, scheme: .dark, reduce: false)
            XCTAssertEqual(image.size, IslandTokens.Size.canvas)
            XCTAssertGreaterThan(try opaquePixels(image), 0, "\(name) painted nothing")
            try save(image, name: "\(name)-dark")
        }
    }

    func testFlatTopAndBoundedBottom() throws {
        for (name, state) in states {
            let bitmap = try bitmap(of: try render(state, scheme: .dark, reduce: false))
            let box = box(for: state)
            // The top row is flush with screen.frame.maxY: it must carry pixels.
            XCTAssertGreaterThan(opaqueIn(row: 0, of: bitmap), 0, "\(name) has no flat top row")
            // Nothing is painted below the silhouette box.
            let limit = Int((box.body.height + box.bottom) * 2) + 4
            if limit < bitmap.pixelsHigh {
                XCTAssertEqual(opaqueBelow(row: limit, of: bitmap), 0, "\(name) paints below its silhouette")
            }
        }
    }

    func testBodyIsOpaqueBlackInBothAppearances() throws {
        for (name, state) in states where state != .collapsed {
            for scheme in [ColorScheme.dark, .light] {
                let bitmap = try bitmap(of: try render(state, scheme: scheme, reduce: false))
                // Sample the left gutter, away from text and the waveform.
                let x = Int((IslandTokens.Size.canvas.width - box(for: state).frameSize.width) / 2 * 2) + 4
                let y = 8
                let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                let red = color?.redComponent ?? 1
                let green = color?.greenComponent ?? 1
                let blue = color?.blueComponent ?? 1
                XCTAssertLessThan(red, 0.05, "\(name)/\(scheme) body is not black")
                XCTAssertLessThan(green, 0.05, "\(name)/\(scheme) body is not black")
                XCTAssertLessThan(blue, 0.05, "\(name)/\(scheme) body is not black")
            }
        }
    }

    func testReduceMotionRendersTheFullState() throws {
        for (name, state) in states {
            let motion = try render(state, scheme: .dark, reduce: false)
            let reduced = try render(state, scheme: .dark, reduce: true)
            XCTAssertGreaterThan(try opaquePixels(reduced), 0, "\(name) is empty under Reduce Motion")
            // Geometry is snapped, so the silhouette's footprint is identical.
            XCTAssertEqual(try opaquePixels(motion), try opaquePixels(reduced),
                           "\(name) changes footprint under Reduce Motion")
            try save(reduced, name: "\(name)-reduce")
        }
    }

    // MARK: pixel helpers

    private func save(_ image: NSImage, name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
        })
        try data.write(to: url.appendingPathComponent("island-\(name).png"))
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    }

    private func opaquePixels(_ image: NSImage) throws -> Int {
        let rep = try bitmap(of: image)
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { count += 1 }
            }
        }
        return count
    }

    private func opaqueIn(row: Int, of rep: NSBitmapImageRep) -> Int {
        (0..<rep.pixelsWide).filter { (rep.colorAt(x: $0, y: row)?.alphaComponent ?? 0) > 0 }.count
    }

    private func opaqueBelow(row: Int, of rep: NSBitmapImageRep) -> Int {
        guard row < rep.pixelsHigh else { return 0 }
        var count = 0
        for y in row..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { count += 1 }
            }
        }
        return count
    }
}
