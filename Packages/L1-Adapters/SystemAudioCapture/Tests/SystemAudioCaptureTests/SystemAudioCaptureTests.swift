import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowSystemAudioCapture

final class SystemAudioCaptureTests: XCTestCase {
    func testAutomaticPrefersProcessTap() async throws {
        let tap = FakeBackend(kind: .processTap)
        let sck = FakeBackend(kind: .screenCaptureKit)
        let capture = SystemAudioCapture(preference: .automatic) { _ in [tap, sck] }

        _ = try await capture.start()
        XCTAssertEqual(capture.activeBackend, .processTap)
        XCTAssertEqual(tap.startCount, 1)
        XCTAssertEqual(sck.startCount, 0)
        await capture.stop()
        XCTAssertNil(capture.activeBackend)
        XCTAssertEqual(tap.stopCount, 1)
    }

    func testFallsBackToScreenCaptureKitWhenTapFails() async throws {
        let tap = FakeBackend(kind: .processTap, startError: .startFailed("tap unavailable"))
        let sck = FakeBackend(kind: .screenCaptureKit)
        let capture = SystemAudioCapture(preference: .automatic) { _ in [tap, sck] }

        _ = try await capture.start()
        XCTAssertEqual(capture.activeBackend, .screenCaptureKit)
        XCTAssertEqual(tap.stopCount, 1)
        XCTAssertEqual(sck.startCount, 1)
        await capture.stop()
    }

    func testBothBackendsFailingReportsEveryReason() async {
        let tap = FakeBackend(kind: .processTap, startError: .startFailed("tap unavailable"))
        let sck = FakeBackend(kind: .screenCaptureKit, startError: .startFailed("no display"))
        let capture = SystemAudioCapture(preference: .automatic) { _ in [tap, sck] }

        do {
            _ = try await capture.start()
            XCTFail("expected failure")
        } catch let error as SuperflowError {
            guard case .audioFailure(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("Core Audio process tap"))
            XCTAssertTrue(message.contains("ScreenCaptureKit"))
            XCTAssertTrue(message.contains("no display"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertNotNil(capture.failureDescription)
    }

    func testPermissionDenialSurfacesAsPermissionDenied() async {
        let tap = FakeBackend(kind: .processTap, startError: .permissionDenied)
        let sck = FakeBackend(kind: .screenCaptureKit, startError: .permissionDenied)
        let capture = SystemAudioCapture(preference: .automatic) { _ in [tap, sck] }

        do {
            _ = try await capture.start()
            XCTFail("expected failure")
        } catch let error as SuperflowError {
            guard case .permissionDenied(let label) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(label, Permission.systemAudio.label)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testStartIsNotReentrantAndStopIsIdempotent() async throws {
        let tap = FakeBackend(kind: .processTap)
        let capture = SystemAudioCapture(preference: .processTap) { _ in [tap] }

        _ = try await capture.start()
        do {
            _ = try await capture.start()
            XCTFail("expected invalidState")
        } catch let error as SuperflowError {
            guard case .invalidState = error else { return XCTFail("unexpected \(error)") }
        } catch {
            XCTFail("unexpected error \(error)")
        }
        await capture.stop()
        await capture.stop()
        XCTAssertEqual(tap.stopCount, 1)
    }

    func testStreamsDeliverSamplesAndStoppedEvent() async throws {
        let tap = FakeBackend(kind: .processTap)
        let capture = SystemAudioCapture(preference: .processTap) { _ in [tap] }
        let streams = try await capture.start()

        tap.emit(AudioChunk(samples: [0.25, 0.5], startSample: 0, source: .system))
        tap.emitEvent(.routeChanged)

        var samples: [AudioChunk] = []
        var events: [AudioEvent] = []
        for await chunk in streams.samples {
            samples.append(chunk)
            if samples.count == 1 { break }
        }
        for await event in streams.events {
            events.append(event)
            if events.count == 1 { break }
        }
        XCTAssertEqual(samples.first?.samples, [0.25, 0.5])
        XCTAssertEqual(events, [.routeChanged])
        await capture.stop()
    }

    func testBackendFailureEventIsForwardedAndStopClosesStreams() async throws {
        let tap = FakeBackend(kind: .processTap)
        let capture = SystemAudioCapture(preference: .processTap) { _ in [tap] }
        let streams = try await capture.start()

        tap.fail("stream died")
        var events: [AudioEvent] = []
        for await event in streams.events {
            events.append(event)
        }
        XCTAssertEqual(events, [.failed("stream died")])
        await capture.stop()
        XCTAssertEqual(tap.stopCount, 1)
    }

    func testPreferenceRestrictsCandidates() async throws {
        let sck = FakeBackend(kind: .screenCaptureKit)
        let capture = SystemAudioCapture(preference: .screenCaptureKit) { _ in [sck] }
        _ = try await capture.start()
        XCTAssertEqual(capture.activeBackend, .screenCaptureKit)
        await capture.stop()
    }
}

/// Test double for a capture transport. It keeps the stream continuations so a
/// test can inject samples, route changes and stream death synchronously.
private final class FakeBackend: SystemAudioBackend, @unchecked Sendable {
    let kind: SystemAudioBackendKind
    private let startError: SystemAudioCaptureFailure?
    private let lock = NSLock()
    private var sampleContinuation: AsyncStream<AudioChunk>.Continuation?
    private var eventContinuation: AsyncStream<AudioEvent>.Continuation?
    private var starts = 0
    private var stops = 0

    init(kind: SystemAudioBackendKind, startError: SystemAudioCaptureFailure? = nil) {
        self.kind = kind
        self.startError = startError
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func start() async throws -> AudioStreams {
        if let startError { throw startError }
        lock.withLock { starts += 1 }
        let (samples, sampleContinuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(16))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16))
        lock.withLock {
            self.sampleContinuation = sampleContinuation
            self.eventContinuation = eventContinuation
        }
        return AudioStreams(samples: samples, events: events)
    }

    func stop() async {
        let state = lock.withLock { () -> (AsyncStream<AudioChunk>.Continuation?,
                                            AsyncStream<AudioEvent>.Continuation?) in
            stops += 1
            let value = (sampleContinuation, eventContinuation)
            sampleContinuation = nil
            eventContinuation = nil
            return value
        }
        state.0?.finish()
        state.1?.yield(.stopped)
        state.1?.finish()
    }

    func emit(_ chunk: AudioChunk) {
        lock.withLock { sampleContinuation }?.yield(chunk)
    }

    func emitEvent(_ event: AudioEvent) {
        lock.withLock { eventContinuation }?.yield(event)
    }

    func fail(_ message: String) {
        let state = lock.withLock { () -> (AsyncStream<AudioChunk>.Continuation?,
                                            AsyncStream<AudioEvent>.Continuation?) in
            let value = (sampleContinuation, eventContinuation)
            sampleContinuation = nil
            eventContinuation = nil
            return value
        }
        state.0?.finish()
        state.1?.yield(.failed(message))
        state.1?.finish()
    }
}
