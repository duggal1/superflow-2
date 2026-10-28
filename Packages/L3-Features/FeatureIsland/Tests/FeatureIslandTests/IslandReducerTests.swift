import XCTest
@testable import SuperflowFeatureIsland

final class IslandReducerTests: XCTestCase {
    private let transcript = IslandTranscript(text: "Hello", bundleID: "com.apple.TextEdit",
                                              appName: "TextEdit", date: Date(timeIntervalSince1970: 0),
                                              words: 1)
    private let sample = IslandPhase.listening

    func testHoldBeganAlwaysStartsListening() {
        let phases: [IslandPhase] = [.idle, .hover, .listening, .processing, .landed(words: 3),
                                     .failed(transcript), .recent(nil)]
        for phase in phases {
            XCTAssertEqual(IslandReducer.reduce(phase, .holdBegan(nil)), .listening)
        }
    }

    func testHoldEndedOnlyLeavesListening() {
        XCTAssertEqual(IslandReducer.reduce(.listening, .holdEnded), .processing)
        XCTAssertEqual(IslandReducer.reduce(.idle, .holdEnded), .idle)
        XCTAssertEqual(IslandReducer.reduce(.hover, .holdEnded), .hover)
        XCTAssertEqual(IslandReducer.reduce(.processing, .holdEnded), .processing)
        XCTAssertEqual(IslandReducer.reduce(.landed(words: 1), .holdEnded), .landed(words: 1))
        XCTAssertEqual(IslandReducer.reduce(.failed(transcript), .holdEnded), .failed(transcript))
        XCTAssertEqual(IslandReducer.reduce(.recent(nil), .holdEnded), .recent(nil))
    }

    func testCancelledOnlyLeavesBusy() {
        XCTAssertEqual(IslandReducer.reduce(.listening, .cancelled), .idle)
        XCTAssertEqual(IslandReducer.reduce(.processing, .cancelled), .idle)
        for phase in [IslandPhase.idle, .hover, .landed(words: 2), .failed(transcript), .recent(nil)] {
            XCTAssertEqual(IslandReducer.reduce(phase, .cancelled), phase)
        }
    }

    func testLandedOnlyLandsWhileBusy() {
        XCTAssertEqual(IslandReducer.reduce(.listening, .landed(words: 4)), .landed(words: 4))
        XCTAssertEqual(IslandReducer.reduce(.processing, .landed(words: 4)), .landed(words: 4))
        XCTAssertEqual(IslandReducer.reduce(.landed(words: 1), .landed(words: 4)), .landed(words: 1))
        XCTAssertEqual(IslandReducer.reduce(.idle, .landed(words: 4)), .idle)
        XCTAssertEqual(IslandReducer.reduce(.hover, .landed(words: 4)), .hover)
        XCTAssertEqual(IslandReducer.reduce(.failed(transcript), .landed(words: 4)),
                       .failed(transcript))
        XCTAssertEqual(IslandReducer.reduce(.recent(nil), .landed(words: 4)), .recent(nil))
    }

    func testPasteFailedOnlyFailsWhileBusy() {
        XCTAssertEqual(IslandReducer.reduce(.listening, .pasteFailed(transcript)),
                       .failed(transcript))
        XCTAssertEqual(IslandReducer.reduce(.processing, .pasteFailed(transcript)),
                       .failed(transcript))
        XCTAssertEqual(IslandReducer.reduce(.idle, .pasteFailed(transcript)), .idle)
        XCTAssertEqual(IslandReducer.reduce(.hover, .pasteFailed(transcript)), .hover)
        XCTAssertEqual(IslandReducer.reduce(.landed(words: 1), .pasteFailed(transcript)),
                       .landed(words: 1))
        XCTAssertEqual(IslandReducer.reduce(.recent(nil), .pasteFailed(transcript)), .recent(nil))
    }

    func testDismissOnlyClosesDismissable() {
        XCTAssertEqual(IslandReducer.reduce(.failed(transcript), .dismissed), .idle)
        XCTAssertEqual(IslandReducer.reduce(.recent(nil), .dismissed), .idle)
        XCTAssertEqual(IslandReducer.reduce(.landed(words: 1), .dismissed), .idle)
        for phase in [IslandPhase.idle, .hover, .listening, .processing] {
            XCTAssertEqual(IslandReducer.reduce(phase, .dismissed), phase)
        }
    }

    func testSamplePhaseIsListening() {
        XCTAssertEqual(sample, .listening)
    }
}
