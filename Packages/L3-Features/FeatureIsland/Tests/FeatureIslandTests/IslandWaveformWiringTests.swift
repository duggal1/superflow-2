import AppKit
import SwiftUI
import XCTest
@testable import SuperflowFeatureIsland

/// Two things have to be true for the meter to appear on an fn press: the model
/// must receive microphone levels, and the view must actually paint blue cells.
/// Both are covered here, so "the waveform did not render" can be split into a
/// data fault and a drawing fault.
@MainActor
final class IslandWaveformWiringTests: XCTestCase {
    private final class LevelFeed: IslandFeed, @unchecked Sendable {
        let levels: AsyncStream<Float>
        private let continuation: AsyncStream<Float>.Continuation

        init() {
            let pair = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(8))
            levels = pair.stream
            continuation = pair.continuation
        }

        func push(_ level: Float) { continuation.yield(level) }

        var events: AsyncStream<IslandEvent> { AsyncStream { $0.finish() } }
        func lastTranscript() -> IslandTranscript? { nil }
        var storesTranscripts: Bool { true }
    }

    private func geometry() -> NotchGeometry {
        NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                      safeTop: 32, leftWidth: 620, rightWidth: 620, scale: 2)
    }

    func testHoldBeganOpensListening() {
        let model = IslandModel(feed: LevelFeed(), geometry: geometry())
        model.send(.holdBegan(IslandTarget(bundleID: "com.apple.TextEdit", name: "TextEdit")))
        XCTAssertEqual(model.phase, .listening)
    }

    func testLevelsBecomeWaveformHistory() async throws {
        let feed = LevelFeed()
        let model = IslandModel(feed: feed, geometry: geometry())
        model.send(.holdBegan(IslandTarget(bundleID: "com.apple.TextEdit", name: "TextEdit")))

        for _ in 0..<10 {
            feed.push(0.9)
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(200))

        model.meter.advance(Date().timeIntervalSinceReferenceDate)
        XCTAssertGreaterThan(model.meter.shown, 0,
                             "fn opened the Island but no level reached the meter")
    }

    func testListeningPaintsBlueCellsInTheRightWing() throws {
        let model = IslandModel(feed: LevelFeed(), geometry: geometry())
        model.send(.holdBegan(IslandTarget(bundleID: "com.apple.TextEdit", name: "TextEdit")))
        model.meter.ingest(1)
        model.meter.advance(Date().timeIntervalSinceReferenceDate)

        let image = try render(model)
        let rect = IslandLayout.box(.listening, geometry()).frameSize
        let left = (IslandLayout.canvas.width - rect.width) / 2 + rect.width - 56
        let blue = bluePixels(in: image, x: Int(left * 2)..<Int((left + 56) * 2), y: 0..<Int(32 * 2))
        XCTAssertGreaterThan(blue, 20, "the meter drew no lit cells in the trailing wing")
    }

    /// The "no waveform" bug in one assertion: silence must still paint a
    /// visible blue dotted line. The old meter drew it in `controlPressed`
    /// (near-black) on a black Island, so an idle input looked like a dead view.
    func testSilenceIsAVisibleBlueDottedLine() throws {
        let renderer = ImageRenderer(content: IslandPixelMeter(meter: IslandMeterModel()))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let blue = bluePixels(in: image, x: 0..<64, y: 0..<40)
        XCTAssertGreaterThan(blue, 0, "silence drew nothing; the meter reads as dead")
    }

    func testARefusalNoticeReplacesTheMeterInsteadOfVanishing() {
        let model = IslandModel(feed: LevelFeed(), geometry: geometry())
        model.send(.holdBegan(IslandTarget(bundleID: "com.apple.TextEdit", name: "TextEdit")))
        model.send(.notice(IslandNotice(kind: .info,
                                        title: "Can't listen yet.",
                                        detail: "The model is still loading.")))
        guard case .notice(let notice) = model.phase else {
            return XCTFail("a refused start left the Island in \(model.phase)")
        }
        XCTAssertEqual(notice.title, "Can't listen yet.")
    }

    private func render(_ model: IslandModel) throws -> NSImage {
        let renderer = ImageRenderer(content: IslandRoot(model: model))
        renderer.scale = 2
        renderer.proposedSize = .init(IslandLayout.canvas)
        var result: NSImage?
        renderer.render(rasterizationScale: 2) { size, draw in
            let w = Int(size.width * 2)
            let h = Int(size.height * 2)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: 2, y: 2)
            draw(ctx)
            if let cg = ctx.makeImage() { result = NSImage(cgImage: cg, size: size) }
        }
        return try XCTUnwrap(result)
    }

    private func bluePixels(in image: NSImage, x: Range<Int>, y: Range<Int>) -> Int {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        var count = 0
        for py in y where py < rep.pixelsHigh {
            for px in x where px < rep.pixelsWide {
                guard let colour = rep.colorAt(x: px, y: py)?
                    .usingColorSpace(.deviceRGB) else { continue }
                if colour.blueComponent > 0.45, colour.blueComponent > colour.redComponent + 0.2 {
                    count += 1
                }
            }
        }
        return count
    }
}
