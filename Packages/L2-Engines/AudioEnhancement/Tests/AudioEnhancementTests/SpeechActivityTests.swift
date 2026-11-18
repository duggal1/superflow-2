import Foundation
import XCTest
@testable import SuperflowAudioEnhancement

/// Deterministic audio fixtures. Speech is a harmonically rich, syllable-gated
/// 130 Hz source; noise is a fixed-seed LCG so every assertion is reproducible.
private enum Fixture {
    static let rate: Float = 16_000

    static func speech(rms target: Float, milliseconds: Int) -> [Float] {
        let count = Int(rate * Float(milliseconds) / 1_000)
        var output = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Float(i) / rate
            let syllable: Float = (t * 4).truncatingRemainder(dividingBy: 1) < 0.65 ? 1 : 0.08
            let wave = sin(2 * .pi * 130 * t) + 0.6 * sin(2 * .pi * 260 * t) + 0.3 * sin(2 * .pi * 390 * t)
            output[i] = syllable * wave
        }
        return scale(output, to: target)
    }

    static func noise(rms target: Float, milliseconds: Int, seed: UInt32 = 0x2545_F491) -> [Float] {
        let count = Int(rate * Float(milliseconds) / 1_000)
        var state = seed
        var output = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 1_664_525 &+ 1_013_904_223
            output[i] = Float(state) / Float(UInt32.max) * 2 - 1
        }
        return scale(output, to: target)
    }

    static func silence(milliseconds: Int) -> [Float] {
        [Float](repeating: 0, count: Int(rate * Float(milliseconds) / 1_000))
    }

    static func scale(_ input: [Float], to target: Float) -> [Float] {
        let energy = input.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(1, input.count))
        let current = energy.squareRoot()
        guard current > 0 else { return input }
        let factor = target / current
        return input.map { $0 * factor }
    }

    static func rms(_ samples: [Float]) -> Float {
        (samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
    }
}

final class SpeechActivityTests: XCTestCase {
    func testVADHearsQuietSpeechAndRejectsNoise() {
        var detector = SpeechActivityDetector()
        let quiet = detector.verdicts(for: Fixture.speech(rms: 0.003, milliseconds: 400))
        XCTAssertTrue(quiet.contains(true), "a -50 dBFS whisper must be heard")
        XCTAssertTrue(detector.isConfirmedSpeech)

        detector.reset()
        let noise = detector.verdicts(for: Fixture.noise(rms: 0.001, milliseconds: 400))
        XCTAssertFalse(noise.contains(true), "steady low-level noise is not speech")
        XCTAssertFalse(detector.isConfirmedSpeech)
    }

    func testVADRejectsShortClicks() {
        var detector = SpeechActivityDetector()
        let click = Fixture.speech(rms: 0.05, milliseconds: 20) // one frame
        let stream = Fixture.silence(milliseconds: 200) + click + Fixture.silence(milliseconds: 200)
        _ = detector.verdicts(for: stream)
        XCTAssertFalse(detector.isConfirmedSpeech, "a single loud frame is a click, not speech")
    }

    func testVADBoundariesClingToSpeechWithHangover() {
        var detector = SpeechActivityDetector()
        let stream = Fixture.silence(milliseconds: 200)
            + Fixture.speech(rms: 0.01, milliseconds: 400)
            + Fixture.silence(milliseconds: 200)
        let verdicts = detector.verdicts(for: stream)
        let trueIndexes = verdicts.enumerated().filter(\.element).map(\.offset)
        XCTAssertFalse(trueIndexes.isEmpty)
        XCTAssertLessThanOrEqual(trueIndexes.first ?? Int.max, 11, "attack must be immediate")
        XCTAssertGreaterThanOrEqual(trueIndexes.last ?? -1, 29, "hangover must cover the word tail")
        XCTAssertTrue(detector.isConfirmedSpeech)
    }

    func testLongAudioCutsAtSilenceMidpoints() {
        var first = Fixture.speech(rms: 0.02, milliseconds: 7_000)
        first += Fixture.silence(milliseconds: 400)
        first += Fixture.speech(rms: 0.02, milliseconds: 6_600)
        first += Fixture.silence(milliseconds: 400)
        first += Fixture.speech(rms: 0.02, milliseconds: 5_900)
        let cuts = SilenceChunker.cuts(first, targetChunks: 3)
        XCTAssertEqual(cuts.count, 2)
        for cut in cuts {
            let seconds = Float(cut) / Fixture.rate
            XCTAssertTrue(abs(seconds - 7.2) < 1.0 || abs(seconds - 14.4) < 1.0,
                          "cut at \(seconds)s is not inside a real silence")
        }
    }

    func testLowVolumeSpeechIsLiftedToTargetLoudness() {
        let whisper = Fixture.speech(rms: 0.003, milliseconds: 400)
        XCTAssertLessThan(Fixture.rms(whisper), 0.005, "fixture must reproduce the bug")
        var leveler = AudioLeveler()
        var last = whisper
        // Three successive utterances, as a recognizer sees them. Re-processing
        // the same already-loud buffer would be a test artifact, not streaming.
        for _ in 0..<3 {
            var block = whisper
            _ = leveler.level(&block)
            last = block
        }
        let outputRMS = Fixture.rms(last)
        XCTAssertGreaterThan(outputRMS, 0.12, "whisper must reach ASR-usable loudness")
        XCTAssertLessThan(outputRMS, 0.25)
        XCTAssertLessThanOrEqual(last.map(abs).max() ?? 1, AudioLeveler.peakLimit + 0.001)
    }

    func testNoiseFloorIsAttenuatedNotAmplified() {
        let noise = Fixture.noise(rms: 0.001, milliseconds: 200)
        let inputRMS = Fixture.rms(noise)
        var leveler = AudioLeveler()
        var block = noise
        for _ in 0..<3 { _ = leveler.level(&block) }
        XCTAssertLessThan(Fixture.rms(block), inputRMS, "noise must not be amplified")
    }

    func testMixedSpeechNoiseImprovesSignalToNoiseRatio() {
        let speech = Fixture.speech(rms: 0.003, milliseconds: 400)
        let noise = Fixture.noise(rms: 0.001, milliseconds: 400, seed: 99)
        let mixed = zip(speech, noise).map(+)
        let before = Fixture.rms(speech) / Fixture.rms(noise)

        var clarity = VoiceClarity()
        var leveler = AudioLeveler()
        var enhanced = mixed
        clarity.apply(&enhanced)
        _ = leveler.level(&enhanced)
        let after = Fixture.rms(enhanced) / Fixture.rms(noise)
        XCTAssertGreaterThan(after, before * 2, "enhanced speech must dominate the noise floor")
    }
}
