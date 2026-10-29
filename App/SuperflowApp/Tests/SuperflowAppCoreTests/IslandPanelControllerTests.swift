import AppKit
import SuperflowFeatureIsland
import XCTest
@testable import SuperflowAppCore

@MainActor
final class IslandPanelControllerTests: XCTestCase {
    private struct Feed: IslandFeed {
        let transcript = IslandTranscript(text: "Cleaned words", bundleID: nil, appName: nil,
                                          date: Date(timeIntervalSince1970: 100), words: 2)
        var events: AsyncStream<IslandEvent> { AsyncStream { $0.finish() } }
        var levels: AsyncStream<Float> { AsyncStream { $0.finish() } }
        var storesTranscripts: Bool { true }
        func lastTranscript() -> IslandTranscript? { transcript }
        func history(limit: Int) -> [IslandTranscript] { [transcript] }
    }

    func testHistoryCanCopyUsingReturnAndDismissUsingEscape() throws {
        let (controller, panel) = try makeController()
        defer { panel.close() }
        let model = controller.model
        model.configure(IslandPrefs(alwaysOn: true))
        model.send(.notchClicked)
        settle()
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.isKeyWindow)
        NSPasteboard.general.clearContents()
        try press(code: 36, characters: "\r", in: panel)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), Feed().transcript.text)
        try press(code: 53, characters: "\u{1b}", in: panel)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testMeetingPanelTakesFocusAndEscapeOnlyCollapsesIt() throws {
        let (controller, panel) = try makeController()
        defer { panel.close() }
        let model = controller.model
        model.send(.meetingBegan(nil))
        XCTAssertFalse(panel.canBecomeKey)
        model.send(.notchClicked)
        XCTAssertEqual(model.phase, .meetingPanel)
        XCTAssertTrue(panel.canBecomeKey)
        try press(code: 53, characters: "\u{1b}", in: panel)
        XCTAssertEqual(model.phase, .meeting)
        XCTAssertFalse(panel.canBecomeKey)
        model.send(.cancelled)
    }

    func testFailureKeepsFocusInTheTargetAppAndLiveShelfReceivesClicks() throws {
        let (controller, panel) = try makeController()
        defer { panel.close() }
        let model = controller.model
        model.configure(IslandPrefs(alwaysOn: true, liveText: true))
        let host = try XCTUnwrap(panel.contentView as? IslandHostingView)
        XCTAssertTrue(host.containsPoint(CGPoint(x: IslandLayout.canvas.width / 2, y: 10)))
        model.send(.holdBegan(nil))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(host.containsPoint(CGPoint(x: IslandLayout.canvas.width / 2,
                                                 y: model.geometry.band + 20)))
        model.send(.pasteFailed(Feed().transcript))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(host.containsPoint(CGPoint(x: 0, y: IslandLayout.canvas.height - 1)))
    }

    private func makeController() throws -> (IslandController, IslandPanel) {
        let app = NSApplication.shared
        let existing = Set(app.windows.map(\.windowNumber))
        let geometry = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     safeTop: 32, leftWidth: 620, rightWidth: 620, scale: 2)
        let controller = IslandController(model: IslandModel(feed: Feed(), geometry: geometry))
        controller.start()
        let panel = try XCTUnwrap(app.windows.compactMap { $0 as? IslandPanel }
            .first { !existing.contains($0.windowNumber) })
        return (controller, panel)
    }

    private func press(code: UInt16, characters: String, in panel: NSPanel) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        panel.sendEvent(event)
        settle()
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}
