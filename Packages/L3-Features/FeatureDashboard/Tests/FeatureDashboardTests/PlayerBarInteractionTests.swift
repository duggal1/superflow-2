import AppKit
import AVFoundation
import SwiftUI
import SuperflowKernel
import SuperflowTestKit
import SuperflowUIComponents
import XCTest
@testable import SuperflowFeatureDashboard

@MainActor
final class PlayerBarInteractionTests: XCTestCase {
    func testDashboardButtonsPauseAndResume() async throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160_000))
        buffer.frameLength = 160_000
        for index in 0..<160_000 { buffer.floatChannelData?[0][index] = Float(sin(Double(index) * 0.1) * 0.03) }
        try file.write(from: buffer)
        let model = RecentDictationViewModel(repository: InMemoryRepository())
        let record = SessionRecord(kind: .dictation, status: .complete, modelProfile: "test")
        let entry = RecentDictationEntry(record: record, raw: "", cleaned: "", audio: url)
        model.play(entry)
        let player = model.audio
        let host = NSHostingView(rootView: PlayerBar(entry: entry, model: model).frame(width: 600, height: 64))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 64), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        defer { window.close() }
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThan(player.duration, 1)
        XCTAssertEqual(player.state, .playing)
        await click(window, at: NSPoint(x: 512, y: 32))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(player.state, .paused)
        let pausedAt = player.time
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(player.time, pausedAt, accuracy: 0.01)
        await click(window, at: NSPoint(x: 512, y: 32))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(player.state, .playing)
        XCTAssertGreaterThanOrEqual(player.time, pausedAt)
    }

    private func click(_ window: NSWindow, at point: NSPoint) async {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 1, clickCount: 1, pressure: 1) {
                NSApplication.shared.sendEvent(event)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
