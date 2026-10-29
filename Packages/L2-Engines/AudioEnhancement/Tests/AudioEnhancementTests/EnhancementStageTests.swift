import Foundation
import SuperflowAudioEnhancement
import SuperflowPorts
import XCTest

private actor DelayedEnhancer: SpeechEnhancer {
    let fail: Bool
    var pending: [Float] = []
    init(fail: Bool = false) { self.fail = fail }
    func isAvailable() -> Bool { true }
    func prepare(progress: @escaping @Sendable (Double) -> Void) { progress(1) }
    func begin() { pending = [] }
    func process(_ samples: [Float]) throws -> [Float] {
        if fail, !pending.isEmpty { throw CancellationError() }
        let output = pending.map { $0 * 0.5 }
        pending = samples
        return output
    }
    func finish() -> [Float] { defer { pending = [] }; return pending.map { $0 * 0.5 } }
    func reset() { pending = [] }
}

final class EnhancementStageTests: XCTestCase, @unchecked Sendable {
    func testDelayedSignalAndTailPreserveEveryPosition() async {
        let enhancer = DelayedEnhancer()
        var stage = EnhancementStage(enhancer: enhancer, enabled: true)
        let first = await stage.push([1, 2])
        let second = await stage.push([3, 4, 5])
        let tail = await stage.finish()
        XCTAssertEqual(first + second + tail, [0.5, 1, 1.5, 2, 2.5])
    }
    func testFailureSubstitutesPendingRawWithoutLosingSamples() async {
        var stage = EnhancementStage(enhancer: DelayedEnhancer(fail: true), enabled: true)
        let first = await stage.push([1, 2])
        let second = await stage.push([3, 4, 5])
        let third = await stage.push([6])
        let tail = await stage.finish()
        XCTAssertEqual(first + second + third + tail, [1, 2, 3, 4, 5, 6])
        XCTAssertNotNil(stage.failure)
    }
    func testDisabledPassesRawAudio() async {
        var stage = EnhancementStage(enhancer: DelayedEnhancer(), enabled: false)
        let result = await stage.push([1, 2, 3])
        let tail = await stage.finish()
        XCTAssertEqual(result, [1, 2, 3])
        XCTAssertTrue(tail.isEmpty)
    }
}

private struct StallingEnhancer: SpeechEnhancer {
    func isAvailable() async -> Bool { true }
    func prepare(progress: @escaping @Sendable (Double) -> Void) async {}
    func begin() async {}
    func process(_ samples: [Float]) async -> [Float] { [] }
    func finish() async -> [Float] { [] }
    func reset() async {}
}

extension EnhancementStageTests {
    func testStalledEnhancerReturnsAllAudioAndContinuesInPassthrough() async {
        var stage = EnhancementStage(enhancer: StallingEnhancer(), enabled: true)
        let raw = [Float](repeating: 0.2, count: 20_000)
        let result = await stage.push(raw)
        let next = await stage.push([0.4])
        let tail = await stage.finish()
        XCTAssertEqual(result + next + tail, raw + [0.4])
        XCTAssertNotNil(stage.failure)
    }
}
