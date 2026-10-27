import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest

final class AudioContractTests: XCTestCase {
    func testAudioSourceContractAgainstReplaySource() async throws {
        let source = ReplayAudioSource(samples: Array(repeating: 0.25, count: 8_000),
                                       kind: .mic, chunkSamples: 1_600)
        try await AudioSourceContract(expectedKind: .mic).verify(source)
    }

    func testSpeechRecognizerContractAgainstFake() async throws {
        let recognizer = FakeSpeechRecognizer(isReady: false, script: ["hello contract"])
        try await SpeechRecognizerContract().verify(recognizer)
        let streams = await recognizer.streamsMade
        XCTAssertEqual(streams, 1)
    }

    func testSpeakerDiarizerContractAgainstFake() async throws {
        let diarizer = FakeSpeakerDiarizer()
        try await SpeakerDiarizerContract().verify(diarizer)
        let finished = await diarizer.finished
        XCTAssertEqual(finished, 2)
    }

    func testAudioSourceStartFailureIsReported() async throws {
        let source = ScriptedAudioSource(samples: [], failStart: true)
        do {
            _ = try await source.start()
            XCTFail("expected start to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .audioFailure("scripted start failure"))
        }
    }

    func testRecognizerWarmUpAndStreamFailuresAreReported() async throws {
        let warmUp = FakeSpeechRecognizer(isReady: false, failWarmUp: true)
        do {
            try await warmUp.prepare(profileID: "p", progress: { _ in })
            XCTFail("expected warmUp to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .modelUnavailable("p"))
        }

        let stream = FakeSpeechRecognizer(failMakeStream: true)
        do {
            _ = try await stream.makeStream(profile: "p", source: .mic)
            XCTFail("expected makeStream to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .modelUnavailable("p"))
        }
    }

    func testDiarizerPrepareFailureIsReported() async throws {
        let diarizer = FakeSpeakerDiarizer(failPrepare: true)
        do {
            try await diarizer.prepare(progress: { _ in })
            XCTFail("expected prepare to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .modelUnavailable("diarizer"))
        }
    }
}
