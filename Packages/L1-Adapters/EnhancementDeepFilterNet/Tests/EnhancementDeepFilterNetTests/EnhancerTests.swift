import Foundation
import XCTest
@testable import SuperflowEnhancementDeepFilterNet

final class EnhancerTests: XCTestCase, @unchecked Sendable {
    func testOutputGainBoostsSpeechAndLimitsPeaksWithoutClipping() {
        var gain = EnhancementOutputGain()
        let boosted = gain.apply([0.2, -0.2])
        XCTAssertEqual(boosted[0], 0.264, accuracy: 0.000001)
        XCTAssertEqual(boosted[1], -0.264, accuracy: 0.000001)

        let limited = gain.apply([0.9, -0.9, 1.2, -1.2])
        XCTAssertLessThanOrEqual(limited.map(abs).max() ?? 0, EnhancementOutputGain.peakLimit)
        XCTAssertTrue(limited.allSatisfy(\.isFinite))
    }

    func testPreparationPersistsCompiledModelForTheNextLaunch() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_TEST_ENHANCER"] == "1" else {
            throw XCTSkip("Set SUPERFLOW_TEST_ENHANCER=1 to verify the installed model cache")
        }
        let root = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask).first)
            .appendingPathComponent("Superflow/Models/DeepFilterNet3", isDirectory: true)
        guard await DeepFilterNetModelStore(directory: root).isAvailable() else {
            throw XCTSkip("The checksum-verified model must already be installed")
        }
        try await DeepFilterNetEnhancer(directory: root).prepare()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("DeepFilterNet3-Streaming.mlmodelc").path))
    }

    func testFIRPreservesTimingAcrossArbitraryChunkBoundaries() {
        let signal = (0..<16_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16_000)) }
        var pair = EnhancementResampler()
        var output: [Float] = []
        for offset in stride(from: 0, to: signal.count, by: 137) {
            let block = Array(signal[offset..<min(offset + 137, signal.count)])
            output += pair.downsample(pair.upsample(block))
        }
        output += pair.downsample(pair.upsample([Float](repeating: 0, count: 128)))
        XCTAssertGreaterThanOrEqual(output.count, signal.count)
        let error = zip(signal[200..<15_800], output[200..<15_800]).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(error, 0.002)
    }

    func testRealModelPreservesLengthAndResets() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_TEST_ENHANCER"] == "1" else {
            throw XCTSkip("Opt in to the real model download with SUPERFLOW_TEST_ENHANCER=1")
        }
        let enhancer = DeepFilterNetEnhancer()
        try await enhancer.prepare { _ in }
        let available = await enhancer.isAvailable()
        XCTAssertTrue(available)
        for count in [1, 137, 160, 8_003, 16_000] {
            try await enhancer.begin()
            var output: [Float] = []
            for offset in stride(from: 0, to: count, by: 137) {
                output += try await enhancer.process([Float](repeating: 0.02, count: min(137, count - offset)))
            }
            output += try await enhancer.finish()
            XCTAssertEqual(output.count, count)
            XCTAssertTrue(output.allSatisfy(\.isFinite))
        }
    }
}
