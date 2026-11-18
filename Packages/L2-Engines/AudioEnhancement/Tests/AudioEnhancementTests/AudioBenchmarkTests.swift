import Foundation
import XCTest
@testable import SuperflowAudioEnhancement

private struct AudioBenchmark: Encodable {
    let fixture: String
    let inputRMS: Double
    let legacyRMS: Double
    let currentRMS: Double
    let inputPeak: Double
    let legacyPeak: Double
    let currentPeak: Double
    let legacyGainApplied: Bool
    let vadSpeechDetected: Bool
    let noiseFloorBefore: Double
    let noiseFloorAfter: Double
    let snrBefore: Double
    let snrAfter: Double
}

/// Writes measured before/after loudness to .proof/performance/audio-enhancement.json.
/// `legacy` reproduces the pre-fix AGC exactly: freeze below 0.005 RMS, 16x cap.
final class AudioBenchmarkTests: XCTestCase {
    private func legacyLevel(_ input: [Float]) -> ([Float], Bool) {
        var gain: Float = 2.0
        var output = input
        var applied = false
        var start = 0
        while start < output.count {
            let end = min(start + 320, output.count)
            var sumSq: Float = 0
            var peak: Float = 0
            for index in start..<end {
                sumSq += output[index] * output[index]
                peak = max(peak, abs(output[index]))
            }
            let rms = (sumSq / Float(end - start)).squareRoot()
            if rms >= AudioLeveler.silenceRMS {
                let desired = min(AudioLeveler.targetRMS / max(rms, 1e-6), 16)
                gain = desired < gain ? gain + (desired - gain) * 0.05 : desired
                let limited = min(gain, AudioLeveler.peakLimit / max(peak, 1e-6))
                gain = limited
                applied = true
                for index in start..<end { output[index] *= limited }
            }
            start = end
        }
        return (output, applied)
    }

    private func rms(_ samples: [Float]) -> Double {
        Double((samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot())
    }

    private func peak(_ samples: [Float]) -> Double { Double(samples.map(abs).max() ?? 0) }

    func testWriteLoudnessBenchmark() throws {
        let whisper = Fixture.speech(rms: 0.003, milliseconds: 400)
        let noise = Fixture.noise(rms: 0.001, milliseconds: 400, seed: 7)
        let (legacy, legacyApplied) = legacyLevel(whisper)
        var current = whisper
        var leveler = AudioLeveler()
        for _ in 0..<3 {
            var block = whisper
            _ = leveler.level(&block)
            current = block
        }
        var detector = SpeechActivityDetector()
        let speechVerdict = detector.verdicts(for: whisper).contains(true)

        var gatedNoise = noise
        var noiseLeveler = AudioLeveler()
        for _ in 0..<3 { _ = noiseLeveler.level(&gatedNoise) }

        let benchmark = AudioBenchmark(
            fixture: "synthetic whisper 130 Hz + harmonics, 4 Hz syllables, 400 ms",
            inputRMS: rms(whisper), legacyRMS: rms(legacy), currentRMS: rms(current),
            inputPeak: peak(whisper), legacyPeak: peak(legacy), currentPeak: peak(current),
            legacyGainApplied: legacyApplied, vadSpeechDetected: speechVerdict,
            noiseFloorBefore: rms(noise), noiseFloorAfter: rms(gatedNoise),
            snrBefore: rms(whisper) / rms(noise), snrAfter: rms(current) / rms(gatedNoise))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(benchmark)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../..", isDirectory: true).standardizedFileURL
        let out = root.appendingPathComponent(".proof/performance/audio-enhancement.json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: out)
        NSLog("AUDIO_BENCH legacy=\(benchmark.legacyRMS) current=\(benchmark.currentRMS) snrBefore=\(benchmark.snrBefore) snrAfter=\(benchmark.snrAfter)")
    }
}

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
    static func noise(rms target: Float, milliseconds: Int, seed: UInt32) -> [Float] {
        let count = Int(rate * Float(milliseconds) / 1_000)
        var state = seed
        var output = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 1_664_525 &+ 1_013_904_223
            output[i] = Float(state) / Float(UInt32.max) * 2 - 1
        }
        return scale(output, to: target)
    }
    static func scale(_ input: [Float], to target: Float) -> [Float] {
        let current = (input.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(1, input.count))).squareRoot()
        guard current > 0 else { return input }
        return input.map { $0 * target / current }
    }
}
