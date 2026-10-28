import XCTest
@testable import SuperflowKernel

final class KernelTests: XCTestCase {
    func testAudioChunkUsesSampleCountForTime() {
        let chunk = AudioChunk(samples: Array(repeating: 0, count: 8_000), startSample: 16_000, source: .mic)

        XCTAssertEqual(chunk.endSample, 24_000)
        XCTAssertEqual(chunk.startMs, 1_000)
        XCTAssertEqual(chunk.endMs, 1_500)
    }

    func testSegmentTimeLabelsStayCompactUntilAnHour() {
        XCTAssertEqual(Segment.timeLabel(125_000), "2:05")
        XCTAssertEqual(Segment.timeLabel(3_725_000), "1:02:05")
    }

    func testLegacySettingsDecodeWithCurrentDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.asrProfile, ModelProfile.nemotron35Streaming.id)
        XCTAssertFalse(settings.onboardingComplete)
        XCTAssertTrue(settings.cleanupEnabled)
    }
}
