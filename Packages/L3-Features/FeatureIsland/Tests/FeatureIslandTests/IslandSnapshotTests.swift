import AppKit
import SwiftUI
import XCTest
@testable import SuperflowFeatureIsland

private struct StubFeed: IslandFeed {
    var last: IslandTranscript?
    var stores = true
    var rows: [IslandTranscript] = []

    var events: AsyncStream<IslandEvent> { AsyncStream { $0.finish() } }
    var levels: AsyncStream<Float> { AsyncStream { $0.finish() } }
    func lastTranscript() -> IslandTranscript? { last }
    func history(limit: Int) -> [IslandTranscript] { Array(rows.prefix(limit)) }
    var storesTranscripts: Bool { stores }
}

/// Renders every stable state at 2x. The assertions are structural (nothing
/// outside the canvas, the top row is flush) so they do not depend on a golden
/// file that a font update can move.
@MainActor
final class IslandSnapshotTests: XCTestCase {
    private let transcript = IslandTranscript(
        text: "The budget is $12,000, and we meet on Tuesday at the studio on Grand Street.",
        bundleID: "com.apple.TextEdit", appName: "TextEdit",
        date: Date(timeIntervalSince1970: 1_700_000_000), words: 14)

    private func geometry(notch: Bool) -> NotchGeometry {
        notch
            ? NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                            safeTop: 32, leftWidth: 620, rightWidth: 620, scale: 2)
            : NotchGeometry(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                            safeTop: 0, leftWidth: nil, rightWidth: nil, scale: 2)
    }

    private func model(_ geometry: NotchGeometry, last: IslandTranscript? = nil) -> IslandModel {
        IslandModel(feed: StubFeed(last: last), geometry: geometry)
    }

    private func render(_ model: IslandModel) throws -> NSImage {
        let renderer = ImageRenderer(content: IslandRoot(model: model))
        renderer.scale = 2
        renderer.proposedSize = .init(IslandLayout.canvas)
        renderer.isOpaque = false
        var result: NSImage?
        renderer.render(rasterizationScale: 2) { size, draw in
            let w = Int(size.width * 2)
            let h = Int(size.height * 2)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: 2, y: 2)
            draw(ctx)
            if let cgImage = ctx.makeImage() {
                result = NSImage(cgImage: cgImage, size: size)
            }
        }
        return try XCTUnwrap(result)
    }

    func testIdleOnANotchRendersTheNotch() throws {
        let image = try render(model(geometry(notch: true)))
        XCTAssertEqual(image.size, IslandLayout.canvas)
    }

    func testIdleOnADisplayWithoutANotchIsEmpty() throws {
        let model = model(geometry(notch: false))
        let image = try render(model)
        XCTAssertEqual(image.size, IslandLayout.canvas)
        XCTAssertEqual(IslandLayout.box(model.phase, model.geometry).opacity, 0)
    }

    func testListeningRenders() throws {
        let model = model(geometry(notch: true))
        model.send(.holdBegan(IslandTarget(bundleID: "com.apple.TextEdit", name: "TextEdit")))
        XCTAssertNoThrow(try render(model))
        XCTAssertEqual(model.phase, .listening)
    }

    func testProcessingRenders() throws {
        let model = model(geometry(notch: true))
        model.send(.holdBegan(nil))
        model.send(.holdEnded)
        XCTAssertEqual(model.phase, .processing)
        XCTAssertNoThrow(try render(model))
    }

    func testLandedRendersTheCheckmark() throws {
        let model = model(geometry(notch: true))
        model.send(.holdBegan(nil))
        model.send(.landed(words: 12))
        XCTAssertEqual(model.phase, .landed(words: 12))
        XCTAssertNoThrow(try render(model))
    }

    /// A latched dictation is a different promise from a held one, so it must
    /// render with its lock mark and the key shelf in the silhouette.
    func testHandsFreeRendersWithTheHintShelf() throws {
        let model = model(geometry(notch: true))
        model.send(.holdBegan(nil))
        model.send(.handsFreeBegan(nil))
        XCTAssertEqual(model.phase, .handsFree)
        XCTAssertTrue(model.hint)
        XCTAssertEqual(IslandLayout.box(model.phase, model.geometry, hint: model.hint).body.height,
                       model.geometry.band + IslandLayout.hintShelf)
        XCTAssertNoThrow(try render(model))
    }

    /// A meeting is a duration: the band carries the record disc and the clock,
    /// the wing carries the scrolling barcode.
    func testMeetingRendersTheBarcode() throws {
        let model = model(geometry(notch: true))
        model.send(.holdBegan(nil))
        model.send(.meetingBegan(nil))
        XCTAssertEqual(model.phase, .meeting)
        XCTAssertNoThrow(try render(model))
    }

    func testNoticeCardRenders() throws {
        let model = model(geometry(notch: true))
        model.send(.notice(IslandNotice(kind: .milestone, title: "1,000 words.",
                                        detail: "10,000 words dictated with Superflow.")))
        guard case .notice = model.phase else {
            return XCTFail("a notice should be shown, got \(model.phase)")
        }
        XCTAssertNotNil(model.noticeDeadline)
        XCTAssertNoThrow(try render(model))
    }

    func testFailedCardRenders() throws {
        let model = model(geometry(notch: true))
        model.send(.holdBegan(nil))
        model.send(.pasteFailed(transcript))
        XCTAssertEqual(model.phase, .failed(transcript))
        XCTAssertNoThrow(try render(model))
    }

    func testRecentCardRendersWithData() throws {
        let model = model(geometry(notch: true), last: transcript)
        model.openRecent()
        XCTAssertEqual(model.phase, .recent(transcript))
        XCTAssertNoThrow(try render(model))
    }

    func testRecentCardRendersEmpty() throws {
        let model = model(geometry(notch: true))
        model.openRecent()
        XCTAssertEqual(model.phase, .recent(nil))
        XCTAssertNoThrow(try render(model))
    }

    func testCardRendersOnADisplayWithoutANotch() throws {
        let model = model(geometry(notch: false))
        model.send(.holdBegan(nil))
        model.send(.pasteFailed(transcript))
        XCTAssertNoThrow(try render(model))
    }

    func testExpandedStatesRenderAtTwoTimesScale() throws {
        let rows = (0..<5).map { index in
            IslandTranscript(text: transcript.text, bundleID: transcript.bundleID,
                             appName: transcript.appName,
                             date: transcript.date.addingTimeInterval(Double(index)), words: transcript.words)
        }
        let wideNotch = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                      safeTop: 38, leftWidth: 704, rightWidth: 704, scale: 2)
        for (name, geometry) in [("notch", wideNotch), ("external", geometry(notch: false))] {
            let model = IslandModel(feed: StubFeed(last: transcript, rows: rows), geometry: geometry)
            model.configure(IslandPrefs(alwaysOn: true, liveText: true))
            model.live = LiveText(text: String(repeating: "The newest words stay beside the caret. ", count: 8),
                                  speaker: "Alexandra", isFinal: false)
            model.pulse = MeetingPulse(words: 1248, speakers: [
                SpeakerShare(id: "you", name: "You", seconds: 240, isYou: true),
                SpeakerShare(id: "alex", name: "Alexandra", seconds: 180, isYou: false),
                SpeakerShare(id: "sam", name: "Sam", seconds: 60, isYou: false),
            ], current: "Alexandra")
            model.meetingStart = Date().addingTimeInterval(-480)
            model.history = rows
            let phases: [(String, IslandPhase)] = [
                ("idle", .idle), ("hover", .hover), ("live", .listening),
                ("hands-free", .handsFree), ("meeting", .meeting),
                ("meeting-panel", .meetingPanel), ("history", .history),
                ("failed", .failed(transcript)),
                ("notification", .notice(.milestone(words: 1000))),
            ]
            for (state, phase) in phases {
                model.go(phase)
                let bitmap = try hostedBitmap(model)
                let image = try render(model)
                XCTAssertEqual(image.size, IslandLayout.canvas)
                XCTAssertGreaterThan(try opaquePixels(image), 0)
                if let output = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(name)-\(state).png"))
                }
            }
        }
    }

    private func hostedBitmap(_ model: IslandModel) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: IslandRoot(model: model)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: IslandLayout.canvas),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    // MARK: measured pixels

    /// Counts pixels that are not fully transparent. The image is rendered at
    /// 2x, so the canvas is 1040 x 256 device pixels.
    private func opaquePixels(_ image: NSImage) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try XCTUnwrap(cgImage.dataProvider?.data) as Data
        let alphaInfo = cgImage.alphaInfo
        let alphaIndex: Int
        switch alphaInfo {
        case .premultipliedLast, .last, .noneSkipLast: alphaIndex = 3
        case .premultipliedFirst, .first, .noneSkipFirst: alphaIndex = 0
        default: return cgImage.width * cgImage.height
        }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        var count = 0
        for y in 0..<cgImage.height {
            let row = y * cgImage.bytesPerRow
            for x in 0..<cgImage.width {
                if data[row + x * bytesPerPixel + alphaIndex] > 0 { count += 1 }
            }
        }
        return count
    }

    func testIdleOnADisplayWithoutANotchPaintsNothing() throws {
        let image = try render(model(geometry(notch: false)))
        XCTAssertEqual(try opaquePixels(image), 0)
    }

    func testIdleOnANotchIsDrawnStrictlyInsideTheNotchRect() throws {
        let model = model(geometry(notch: true))
        let painted = try opaquePixels(try render(model))
        XCTAssertGreaterThan(painted, 0, "idle on a notch must be drawn, not hidden")

        // At 2x the notch is 544 x 64 device pixels. Nothing may paint outside it.
        let notchPixels = Int(model.geometry.notch.width * model.geometry.notch.height * 4)
        XCTAssertLessThanOrEqual(painted, notchPixels)
        XCTAssertGreaterThan(painted, notchPixels * 9 / 10)
    }

    func testTheSilhouetteIsNotARectangle() throws {
        let rect = CGRect(origin: .zero, size: CGSize(width: 272, height: 32))
        let square = try pixels(NotchShape(top: 0, bottom: 0).fill(.black),
                                size: rect.size)
        let rounded = try pixels(NotchShape(top: 0, bottom: IslandLayout.restBottom).fill(.black),
                                 size: rect.size)
        let notchPixels = Int(rect.width * rect.height * 4)
        XCTAssertEqual(square, notchPixels)
        XCTAssertLessThan(rounded, square)
        XCTAssertGreaterThan(rounded, square * 98 / 100)
    }

    func testWingsAreWiderThanTheNotch() throws {
        let idle = try opaquePixels(try render(model(notchGeometry())))
        let model = model(notchGeometry())
        model.send(.holdBegan(nil))
        let wings = try opaquePixels(try render(model))
        XCTAssertGreaterThan(wings, idle)
    }

    private func pixels(_ view: some View, size: CGSize) throws -> Int {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        return try opaquePixels(try XCTUnwrap(renderer.nsImage))
    }

    private func notchGeometry() -> NotchGeometry { geometry(notch: true) }
}
