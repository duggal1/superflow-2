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

    func testDisfluencySettingsDecodeLegacyThreshold() throws {
        let json = Data(#"{"duplicateThreshold": 4}"#.utf8)
        let settings = try JSONDecoder().decode(DisfluencySettings.self, from: json)

        XCTAssertEqual(settings.tierAThreshold, 2)
        XCTAssertEqual(settings.tierBThreshold, 4)
        XCTAssertEqual(settings.duplicateThreshold, 4)
        XCTAssertTrue(settings.fillerPrepass)
        XCTAssertTrue(settings.collapseRepeatedPhrases)
    }

    func testDisfluencySettingsRoundTripKeepsBothThresholdKeys() throws {
        var settings = DisfluencySettings()
        settings.tierAThreshold = 4
        settings.tierBThreshold = 5
        let data = try JSONEncoder().encode(settings)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["duplicateThreshold"] as? Int, 5)
        XCTAssertEqual(json["tierBThreshold"] as? Int, 5)
        XCTAssertEqual(try JSONDecoder().decode(DisfluencySettings.self, from: data), settings)
    }

    func testDisfluencyThresholdsClampToTheirTiers() throws {
        let json = Data(
            #"{"tierAThreshold": 1, "tierBThreshold": 1, "duplicateThreshold": 1}"#.utf8)
        let settings = try JSONDecoder().decode(DisfluencySettings.self, from: json)

        XCTAssertEqual(settings.tierAThreshold, 2)
        XCTAssertEqual(settings.tierBThreshold, 3)
    }
}
