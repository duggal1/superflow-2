import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowPorts

final class PortsDefaultTests: XCTestCase {
    func testSpeechRecognizerPrepareReportsProgressAndWarmsUp() async throws {
        let recognizer = WarmingRecognizer()
        let progress = Recorder()
        try await recognizer.prepare(profileID: "profile", progress: { progress.append($0) })
        let warmed = await recognizer.warmed
        let ready = await recognizer.isReady
        let available = await recognizer.isAvailable(profileID: "profile")
        XCTAssertEqual(progress.values, [0, 1])
        XCTAssertEqual(warmed, "profile")
        XCTAssertTrue(ready)
        XCTAssertTrue(available)
    }

    func testModelProviderPrepareDelegatesToEnsure() async throws {
        let provider = AvailableModelProvider(url: URL(fileURLWithPath: "/tmp/model"))
        let progress = Recorder()
        try await provider.prepare(profileID: "p", progress: { progress.append($0) })
        let available = await provider.isAvailable(profileID: "p")
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertTrue(available)

        let missing = AvailableModelProvider(url: nil)
        let missingAvailable = await missing.isAvailable(profileID: "p")
        XCTAssertFalse(missingAvailable)
        do {
            try await missing.prepare(profileID: "p", progress: { _ in })
            XCTFail("expected prepare to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .modelUnavailable("p"))
        }
    }

    func testSpeakerDiarizerDefaultsAreSafeNoOps() async throws {
        let diarizer = MinimalDiarizer()
        let ready = await diarizer.isReady()
        XCTAssertTrue(ready)
        try await diarizer.prepare(progress: { _ in })
        await diarizer.beginSession()
        let speaker = await diarizer.speaker(atMs: 0)
        XCTAssertNil(speaker)
    }

    func testNoopLaunchAtLoginRefusesEnable() async throws {
        let controller = NoopLaunchAtLoginController()
        let enabled = await controller.isEnabled()
        XCTAssertFalse(enabled)
        try await controller.setEnabled(false)
        do {
            try await controller.setEnabled(true)
            XCTFail("expected enable to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .invalidState("Launch at login is unavailable."))
        }
    }

    func testGlobeKeyConflictClassification() async {
        XCTAssertFalse(GlobeKeyAction.doNothing.isConflict)
        XCTAssertFalse(GlobeKeyAction.unknown.isConflict)
        XCTAssertTrue(GlobeKeyAction.changeInputSource.isConflict)
        XCTAssertTrue(GlobeKeyAction.emojiAndSymbols.isConflict)
        XCTAssertTrue(GlobeKeyAction.dictation.isConflict)
        // Unset is macOS defaulting to Show Emoji & Symbols, which is a conflict, not an unknown.
        XCTAssertTrue(GlobeKeyAction.notConfigured.isConflict)
        let action = await UnknownGlobeKeyProbe().currentAction()
        XCTAssertEqual(action, .unknown)
    }

    func testCleanOptionsAndInsertionOutcomesHaveStableDefaults() {
        let options = CleanOptions()
        XCTAssertEqual(options.styling, "semi-formal")
        XCTAssertEqual(options.structure, "prose")
        XCTAssertEqual(options.context, "general")
        XCTAssertEqual(options.deadlineMs, 1_500)
        XCTAssertEqual(options.maxNewTokens, 1_024)
        XCTAssertEqual(InsertionOutcome.pasted, .pasted)
        XCTAssertNotEqual(InsertionOutcome.pasted, .blockedSecureField)
    }

    func testNoopMetricsAcceptsSamples() {
        let metrics = NoopMetrics()
        metrics.record("stage", valueMs: 1)
        metrics.event("event", ["key": "value"])
    }

    func testSystemClockIsMonotonic() {
        let clock = SystemTimeSource()
        let first = clock.monotonicNs()
        let second = clock.monotonicNs()
        XCTAssertLessThanOrEqual(first, second)
        XCTAssertLessThanOrEqual(clock.now(), Date().addingTimeInterval(1))
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func append(_ value: Double) { lock.withLock { storage.append(value) } }
    var values: [Double] { lock.withLock { storage } }
}

private actor WarmingRecognizer: SpeechRecognizer {
    private(set) var warmed: String?
    private(set) var isReady = false

    func warmUp(profile: String) async throws {
        warmed = profile
        isReady = true
    }

    func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        EmptyStream()
    }
}

private struct EmptyStream: RecognitionStream {
    let events = AsyncStream<RecognitionEvent> { $0.finish() }
    func feed(_ chunk: AudioChunk) async {}
    func finish() async {}
}

private actor AvailableModelProvider: ModelProvider {
    let url: URL?
    init(url: URL?) { self.url = url }

    func localURL(for profileID: String) async -> URL? { url }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        guard let url else { throw SuperflowError.modelUnavailable(profileID) }
        return url
    }
    func llmModelURL() async -> URL? { nil }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        _ = progress
        throw SuperflowError.modelUnavailable("llm")
    }
}

private actor MinimalDiarizer: SpeakerDiarizer {
    func feed(_ chunk: AudioChunk) async {}
    func speaker(atMs: Int) async -> String? { nil }
    func finish() async {}
}
