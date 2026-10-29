import AppKit
import CoreText
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowTestKit
import SuperflowUIComponents
import SwiftUI
import XCTest
@testable import SuperflowFeatureMeetings

@MainActor
final class MeetingDetailRenderTests: XCTestCase {
    func testTranscriptUsesAvailableWidth() throws {
        let id = SessionID("render")
        let turn = MeetingTurn(index: 0, speakerID: "self", speakerName: "You", startMs: 0, endMs: 9000,
                               text: "We reviewed the budget and agreed on the next steps for the project.",
                               rawText: "We reviewed the budget and agreed on the next steps for the project.", source: .mic)
        let document = MeetingDocument(sessionID: id, title: "Project review", startedAt: Date(), endedAt: nil,
                                       durationMs: 9000, speakers: [], turns: [turn])
        let model = PastMeetingsModel(repository: InMemoryRepository(), inserter: RecordingInserter())
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        _ = CTFontManagerRegisterFontsForURL(root.appendingPathComponent("App/Resources/Fonts/SerifVinci.otf") as CFURL, .process, nil)
        let view = ScrollViewReader { proxy in
            ScrollView { MeetingDetail(model: model, document: document, proxy: proxy, collapse: {})
                .padding(20) }
        }
        .frame(width: 680, height: 360)
        .background(Tok.bg)
        .environment(DialogHost())
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let size = CGSize(width: 680, height: 360)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1360, pixelsHigh: 720,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(bitmap.pixelsWide, 1360)
        if let directory = ProcessInfo.processInfo.environment["MEETING_SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("meeting-detail.png"))
        }
    }
}
