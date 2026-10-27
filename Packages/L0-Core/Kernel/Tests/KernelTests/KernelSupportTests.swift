import Foundation
import SuperflowKernel
import XCTest

final class KernelSupportTests: XCTestCase {
    func testSessionIdentifiersHaveStableShortForm() {
        let id: SessionID = "12345678-aaaa-bbbb-cccc-dddddddddddd"
        XCTAssertEqual(id.short, "12345678")
        XCTAssertEqual(id.description, id.value)
        XCTAssertEqual(SessionID("x"), SessionID("x"))
        XCTAssertNotEqual(SessionID("x"), SessionID("y"))
    }

    func testSegmentBestTextAndTimestampPreferCleanedText() {
        let segment = Segment(sessionID: "s", index: 0, startMs: 3_725_000, endMs: 3_726_000,
                              rawText: "raw", cleanedText: "cleaned")
        XCTAssertEqual(segment.bestText, "cleaned")
        XCTAssertEqual(segment.timestampLabel, "1:02:05")
        XCTAssertEqual(segment.id, "s#0")

        var rawOnly = segment
        rawOnly.cleanedText = nil
        XCTAssertEqual(rawOnly.bestText, "raw")
    }

    func testSessionDurationLabels() {
        let base = SessionRecord(kind: .dictation, startedAt: Date(timeIntervalSince1970: 0),
                                 modelProfile: "p", durationMs: 3_725_000)
        XCTAssertEqual(base.durationLabel, "1h 02m")
        XCTAssertEqual(SessionRecord(kind: .dictation, modelProfile: "p", durationMs: 125_000).durationLabel,
                       "2m 05s")
        XCTAssertEqual(SessionRecord(kind: .dictation, modelProfile: "p", durationMs: 9_000).durationLabel,
                       "9s")
    }

    func testLocalDayRoundTripAndRejectsMalformedInput() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let day = LocalDay.string(for: date, calendar: calendar)
        XCTAssertEqual(day, "2023-11-14")
        XCTAssertEqual(LocalDay.date(from: day, calendar: calendar), calendar.startOfDay(for: date))
        XCTAssertNil(LocalDay.date(from: "not-a-day", calendar: calendar))
        XCTAssertNil(LocalDay.date(from: "2026-01", calendar: calendar))
    }

    func testWordCountIgnoresRepeatedWhitespaceAndNewlines() {
        XCTAssertEqual(wordCount("  one\n two\tthree  "), 3)
        XCTAssertEqual(wordCount(""), 0)
        XCTAssertEqual(wordCount(" \n\t "), 0)
    }

    func testSettingsDecodePartialAndRoundTrip() throws {
        let partial = Data(#"{"theme":"dark","typingWPM":72,"lineFormat":{"minWords":10}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: partial)
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.typingWPM, 72)
        XCTAssertEqual(settings.lineFormat.minWords, 10)
        XCTAssertEqual(settings.lineFormat.preferredMax, 35)
        XCTAssertEqual(settings.gesture.holdMs, 200)

        let encoded = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoded), settings)
    }

    func testModelProfileLookupFallsBackToTheVerifiedDefault() {
        XCTAssertEqual(ModelProfile.byID(ModelProfile.parakeetEOU120M.id),
                       ModelProfile.parakeetEOU120M)
        XCTAssertEqual(ModelProfile.byID("does-not-exist"), .parakeetEOU120M)
        XCTAssertEqual(ModelProfile.all.map(\.id), ModelProfile.all.map(\.id).uniqued())
    }

    func testNVIDIAProfilesExposeStreamingAndBatchModels() {
        let ids = Set(ModelProfile.all.map(\.id))
        XCTAssertTrue(ids.contains(ModelProfile.parakeetUnified.id))
        XCTAssertTrue(ids.contains(ModelProfile.nemotron35Streaming.id))
        XCTAssertTrue(ids.contains(ModelProfile.parakeetTDTV3.id))
        XCTAssertTrue(ModelProfile.all.allSatisfy { $0.vendor == "NVIDIA" })
        XCTAssertTrue(ModelProfile.all.allSatisfy { $0.upstreamRepo.hasPrefix("nvidia/") })

        XCTAssertEqual(ModelProfile.parakeetUnified.upstreamRepo,
                       "nvidia/parakeet-unified-en-0.6b")
        XCTAssertEqual(ModelProfile.nemotron35Streaming.upstreamRepo,
                       "nvidia/nemotron-3.5-asr-streaming-0.6b")
        XCTAssertTrue(ModelProfile.parakeetUnified.supportsLiveDictation)
        XCTAssertTrue(ModelProfile.nemotron35Streaming.supportsLiveDictation)
        XCTAssertEqual(ModelProfile.parakeetUnified.formatLabel, "Streaming")
        XCTAssertEqual(ModelProfile.parakeetUnified.latencyLabel, "640 ms chunks")

        XCTAssertFalse(ModelProfile.parakeetTDTV3.streaming)
        XCTAssertFalse(ModelProfile.parakeetTDTV3.supportsLiveDictation)
        XCTAssertEqual(ModelProfile.parakeetTDTV3.formatLabel, "Batch")
        XCTAssertEqual(ModelProfile.parakeetTDTV3.latencyLabel, "15 s windows")
        XCTAssertEqual(ModelProfile.parakeetTDTV3.upstreamRepo,
                       "nvidia/parakeet-tdt-0.6b-v3")
    }

    func testSuperflowErrorDescriptionsAreUserFacing() {
        XCTAssertEqual(SuperflowError.diskFull.errorDescription,
                       "Not enough free disk space to record safely.")
        XCTAssertEqual(SuperflowError.cancelled.errorDescription, "Cancelled")
        XCTAssertTrue(SuperflowError.permissionDenied("Microphone").errorDescription?
            .contains("Microphone") == true)
        XCTAssertTrue(SuperflowError.invalidState("bad").errorDescription?.contains("bad") == true)
    }

    func testTextSafeCollapsesNewlines() {
        XCTAssertEqual(TextSafe.singleLine(" one\ntwo \n"), "one two")
        XCTAssertEqual(TextSafe.singleLine("\n\n"), "")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
