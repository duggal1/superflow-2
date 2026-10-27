import XCTest
import SuperflowKernel
@testable import SuperflowPorts

final class PortsTests: XCTestCase {
    func testSpeechRecognizerDefaultPreparationWarmsTheRequestedProfile() async throws {
        let recognizer = StubRecognizer()

        let availableBefore = await recognizer.isAvailable(profileID: "profile-a")
        XCTAssertFalse(availableBefore)
        try await recognizer.prepare(profileID: "profile-a", progress: { _ in })
        let availableAfter = await recognizer.isAvailable(profileID: "profile-a")
        let warmedProfile = await recognizer.warmedProfile
        XCTAssertTrue(availableAfter)
        XCTAssertEqual(warmedProfile, "profile-a")
    }
}

private actor StubRecognizer: SpeechRecognizer {
    private(set) var warmedProfile: String?
    private(set) var isReady = false

    func warmUp(profile: String) async throws {
        warmedProfile = profile
        isReady = true
    }

    func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        EmptyRecognitionStream()
    }
}

private struct EmptyRecognitionStream: RecognitionStream {
    let events = AsyncStream<RecognitionEvent> { $0.finish() }

    func feed(_ chunk: AudioChunk) async {}
    func finish() async {}
}
