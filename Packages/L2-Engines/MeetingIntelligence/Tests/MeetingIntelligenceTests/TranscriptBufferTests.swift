import XCTest
@testable import SuperflowMeetingIntelligence

final class TranscriptBufferTests: XCTestCase {
    func testInterleavedPartialsAreReplacedByTheirSpeaker() async {
        let buffer = TranscriptBuffer()
        await buffer.ingest(speaker: .me, text: "hello", isFinal: false)
        await buffer.ingest(speaker: .them, text: "hi", isFinal: false)
        await buffer.ingest(speaker: .me, text: "hello there", isFinal: true)
        let result = await buffer.snapshot()
        XCTAssertTrue(result.contains("ME: hello there"))
        XCTAssertTrue(result.contains("THEM: hi …"))
        XCTAssertEqual(result.components(separatedBy: "ME:").count, 2)
    }

    func testSuppressionDropsPendingAndNewMicSpeech() async {
        let buffer = TranscriptBuffer()
        await buffer.ingest(speaker: .me, text: "pending", isFinal: false)
        await buffer.setSuppressMe(true)
        await buffer.ingest(speaker: .me, text: "secret question", isFinal: true)
        await buffer.ingest(speaker: .them, text: "remote", isFinal: true)
        let result = await buffer.snapshot()
        XCTAssertFalse(result.contains("pending"))
        XCTAssertFalse(result.contains("secret question"))
        XCTAssertTrue(result.contains("remote"))
    }

    func testSnapshotRetainsNewestTextWithinLimit() async {
        let buffer = TranscriptBuffer(capacity: 100)
        await buffer.ingest(speaker: .them, text: String(repeating: "a", count: 200), isFinal: true)
        let result = await buffer.snapshot(maxChars: 30)
        XCTAssertEqual(result.count, 30)
        XCTAssertEqual(result, String(repeating: "a", count: 30))
    }
}
