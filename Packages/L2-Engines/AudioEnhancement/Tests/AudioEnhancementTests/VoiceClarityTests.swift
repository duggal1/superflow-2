import XCTest
@testable import SuperflowAudioEnhancement

final class VoiceClarityTests: XCTestCase {
    private func tone(_ frequency: Float, amplitude: Float = 0.2, seconds: Float = 0.25) -> [Float] {
        let rate: Float = 16_000
        return (0..<Int(rate * seconds)).map { index in
            amplitude * sin(2 * Float.pi * frequency * Float(index) / rate)
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        let tail = samples.suffix(samples.count / 2)
        return (tail.reduce(Float.zero) { $0 + $1 * $1 } / Float(tail.count)).squareRoot()
    }

    func testSilenceAndNonFiniteInputStayFinite() {
        var clarity = VoiceClarity()
        var silence = [Float](repeating: 0, count: 1024)
        clarity.apply(&silence)
        XCTAssertTrue(silence.allSatisfy { $0 == 0 })
        var invalid: [Float] = [.nan, .infinity, 0, -.infinity]
        clarity.apply(&invalid)
        XCTAssertTrue(invalid.allSatisfy(\.isFinite))
    }

    func testSampleCountAndBoundedGain() {
        var clarity = VoiceClarity()
        var samples = tone(1_000)
        let count = samples.count
        clarity.apply(&samples)
        XCTAssertEqual(samples.count, count)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertLessThan(samples.map(abs).max() ?? 0, 0.25)
        XCTAssertGreaterThan(rms(samples), 0.05)
    }

    func testHighPassAttenuatesRumbleMoreThanSpeechBand() {
        var low = VoiceClarity()
        var lowSamples = tone(30)
        low.apply(&lowSamples)
        var speech = VoiceClarity()
        var speechSamples = tone(1_000)
        speech.apply(&speechSamples)
        XCTAssertLessThan(rms(lowSamples), rms(speechSamples) * 0.5)
    }

    func testResetRestoresFilters() {
        var clarity = VoiceClarity()
        var samples = tone(1_000)
        clarity.apply(&samples)
        clarity.reset()
        var silence = [Float](repeating: 0, count: 64)
        clarity.apply(&silence)
        XCTAssertTrue(silence.allSatisfy { abs($0) < 1e-4 })
    }
}
