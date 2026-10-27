import FluidAudio
import SuperflowKernel
import XCTest
@testable import SuperflowDiarizationFluidAudio

final class SpeakerDiarizerTests: XCTestCase {
    func testSingleSpeakerIsSilentUntilAudioArrives() async {
        let diarizer = SingleSpeakerDiarizer()
        let before = await diarizer.speaker(atMs: 0)
        XCTAssertNil(before)
        await diarizer.feed(AudioChunk(samples: [0.1], startSample: 0, source: .system))
        let after = await diarizer.speaker(atMs: 500)
        XCTAssertEqual(after, "remote-1")
        await diarizer.finish()
        let afterFinish = await diarizer.speaker(atMs: 900)
        XCTAssertEqual(afterFinish, "remote-1")
    }

    func testTimelineFindsContainingAndPreviousSegments() {
        let timeline = DiarizationTimeline(segments: [
            DiarizationSegment(startMs: 0, endMs: 1_000, speakerID: "remote-1"),
            DiarizationSegment(startMs: 2_000, endMs: 3_000, speakerID: "remote-2"),
        ])
        XCTAssertEqual(timeline.speaker(atMs: 0), "remote-1")
        XCTAssertEqual(timeline.speaker(atMs: 1_500), "remote-1")
        XCTAssertEqual(timeline.speaker(atMs: 2_500), "remote-2")
        XCTAssertEqual(timeline.speaker(atMs: 9_000), "remote-2")
    }

    func testTimelineMergesAdjacentSameSpeaker() {
        var timeline = DiarizationTimeline()
        timeline.append(DiarizationSegment(startMs: 0, endMs: 500, speakerID: "remote-1"))
        timeline.append(DiarizationSegment(startMs: 520, endMs: 900, speakerID: "remote-1"))
        timeline.append(DiarizationSegment(startMs: 1_000, endMs: 1_500, speakerID: "remote-2"))
        XCTAssertEqual(timeline.segments.count, 2)
        XCTAssertEqual(timeline.segments[0].endMs, 900)
        XCTAssertEqual(timeline.ranges(for: "remote-1").count, 1)
    }

    func testTimelineDoesNotMergeAcrossGap() {
        var timeline = DiarizationTimeline()
        timeline.append(DiarizationSegment(startMs: 0, endMs: 500, speakerID: "remote-1"))
        timeline.append(DiarizationSegment(startMs: 1_000, endMs: 1_500, speakerID: "remote-1"))
        XCTAssertEqual(timeline.segments.count, 2)
    }

    func testInvalidSegmentsAreIgnored() {
        var timeline = DiarizationTimeline()
        timeline.append(DiarizationSegment(startMs: 500, endMs: 100, speakerID: "remote-1"))
        XCTAssertTrue(timeline.segments.isEmpty)
    }

    func testAvailabilityExplainsFallback() {
        XCTAssertFalse(DiarizationAvailability.explanation.isEmpty)
        if !DiarizationAvailability.isLinked {
            XCTAssertTrue(DiarizationAvailability.explanation.contains("Speaker 1"))
        }
    }

    func testSortformerUsesTheStreamingV2_1Configuration() {
        XCTAssertEqual(FluidAudioDiarizer.configuration.modelVariant?.name, "Sortformer_v2.1")
        XCTAssertEqual(FluidAudioDiarizer.configuration.numSpeakers, 4)
        XCTAssertEqual(FluidAudioDiarizer.timelineConfiguration.maxStoredFrames, 0)
        XCTAssertFalse(FluidAudioDiarizer.timelineConfiguration.storeSegments)
    }

    func testSpeakerLabelsAreStableAndCappedAtFour() {
        XCTAssertEqual(SortformerSpeakerLabel.label(forSpeakerIndex: 0), "remote-1")
        XCTAssertEqual(SortformerSpeakerLabel.label(forSpeakerIndex: 1), "remote-2")
        XCTAssertEqual(SortformerSpeakerLabel.label(forSpeakerIndex: 3), "remote-4")
        XCTAssertEqual(SortformerSpeakerLabel.label(forSpeakerIndex: 9), "remote-4")
        XCTAssertEqual(SortformerSpeakerLabel.label(forSpeakerIndex: -1), "remote-1")
    }

    func testTimelineIsCappedInRecordingLength() {
        let segments = (0..<5_000).map {
            DiarizationSegment(startMs: $0 * 200, endMs: $0 * 200 + 50,
                               speakerID: SortformerSpeakerLabel.label(forSpeakerIndex: $0 % 4))
        }
        let timeline = DiarizationTimeline(segments: segments)
        XCTAssertEqual(timeline.segments.count, DiarizationTimeline.maximumSegments)
        XCTAssertEqual(timeline.segments.first?.startMs, (5_000 - 4_096) * 200)
    }

    func testTimelineLookupIsCorrectInAGapAndAtBoundaries() {
        let timeline = DiarizationTimeline(segments: [
            DiarizationSegment(startMs: 0, endMs: 1_000, speakerID: "remote-1"),
            DiarizationSegment(startMs: 2_000, endMs: 3_000, speakerID: "remote-2"),
        ])
        XCTAssertEqual(timeline.speaker(atMs: -1), nil)
        XCTAssertEqual(timeline.speaker(atMs: 1_000), "remote-1")
        XCTAssertEqual(timeline.speaker(atMs: 2_000), "remote-2")
        XCTAssertEqual(timeline.speaker(atMs: 1_500), "remote-1")
    }
}
