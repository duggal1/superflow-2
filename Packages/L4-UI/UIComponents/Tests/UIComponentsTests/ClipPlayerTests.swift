import AVFoundation
import XCTest
@testable import SuperflowUIComponents

@MainActor
final class ClipPlayerTests: XCTestCase {
    func testDecodesAndStartsPlayback() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<16_000 {
            channel[index] = sin(Float(index) * 0.1) * 0.3
        }
        try file.write(from: buffer)

        let decoded = await ClipLoader.load(url)
        let clip = try XCTUnwrap(decoded)
        XCTAssertEqual(clip.sampleRate, 16_000)
        XCTAssertGreaterThan(clip.duration, 0.5)
        XCTAssertFalse(clip.cells.isEmpty, "the spectrogram must be produced")

        let player = ClipPlayer()
        player.load(clip)
        player.play()
        guard case .playing = player.state else {
            return XCTFail("play() did not start the engine")
        }
        player.stop()
        guard case .idle = player.state else {
            return XCTFail("stop() did not return to idle")
        }
    }
}
