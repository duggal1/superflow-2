import Foundation
import XCTest
@testable import SuperflowAudioEnhancement

final class AudioLevelerTests: XCTestCase {
    func testQuietSpeechIsRaisedTowardTarget() {
        var leveler = AudioLeveler()
        // Quiet speech at RMS ~0.02 (-34 dBFS) should be boosted.
        var block = [Float](repeating: 0.02, count: 320)
        _ = leveler.level(&block)
        let boostedRMS = (block.map { $0 * $0 }.reduce(0, +) / Float(block.count)).squareRoot()
        XCTAssertGreaterThan(boostedRMS, 0.02)
        XCTAssertLessThan(boostedRMS, 0.105)
    }

    func testLoudSpeechIsLimitedNotClipped() {
        var leveler = AudioLeveler()
        var block = [Float](repeating: 0.9, count: 320)
        _ = leveler.level(&block)
        XCTAssertLessThanOrEqual(block.max() ?? 1, 0.891001)
    }

    func testSilenceFreezesGain() {
        var leveler = AudioLeveler()
        var speech = [Float](repeating: 0.02, count: 320)
        let gainAfterSpeech = leveler.level(&speech)
        var silence = [Float](repeating: 0, count: 320)
        let gainOnSilence = leveler.level(&silence)
        XCTAssertEqual(gainAfterSpeech, gainOnSilence, accuracy: 0.0001 as Float)
    }

    func testFirstWordNotClippedByRamp() {
        var leveler = AudioLeveler()
        // Word onset inside the block gets the same whole-block gain.
        var block = [Float](repeating: 0.02, count: 320)
        block[0] = 0.05
        _ = leveler.level(&block)
        XCTAssertTrue(block.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(block.max() ?? 0, 0.05)
    }
}
