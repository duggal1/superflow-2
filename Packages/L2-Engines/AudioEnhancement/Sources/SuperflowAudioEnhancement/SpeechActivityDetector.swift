import Foundation

/// Causal voice-activity detector for 16 kHz mono speech.
///
/// Ported ideas (see .proof/performance/report.md): HEX `src/speech_detector.rs`
/// uses a Silero VAD with a 0.4 probability threshold and a 160 ms minimum
/// speech run so short "Ok"/"Ciao" are kept while clicks are rejected; HEX
/// `Media.swift` finds silence midpoints in 50 ms windows for long-audio cuts.
/// We cannot load Silero here, so the score is an energy/ZCR posterior over an
/// adaptive noise floor. It is deterministic, allocation-free per frame and
/// never hides an error: callers decide what to do with `confidence`.
public struct SpeechActivityDetector: Sendable {
    public struct Settings: Sendable {
        public var sampleRate: Float = 16_000
        public var frameMs: Float = 20
        /// Probability-equivalent threshold (HEX uses 0.4 for Silero).
        public var threshold: Float = 0.4
        /// Frames shorter than this are treated as clicks, not speech.
        public var minSpeechMs: Float = 160
        /// Hold the verdict briefly after the last voiced frame so soft tails
        /// and word-final consonants are not cut ("cling to speech").
        public var hangoverMs: Float = 220
        /// Absolute floor below which no frame can be speech (about -66 dBFS).
        public var absoluteFloor: Float = 0.0005
        /// Speech must exceed the learned noise floor by this ratio.
        public var noiseMultiplier: Float = 2.0
        /// Broadband hiss has a high zero-crossing rate; speech at 16 kHz does not.
        public var maxZeroCrossingRate: Float = 0.42
        public var noiseAdaptation: Float = 0.02

        public init() {}
    }

    public let settings: Settings
    private var noiseRMS: Float
    private var consecutiveVoiced = 0
    private var hangover = 0
    private var confirmed = false

    /// True once at least `minSpeechMs` of voiced frames were seen. Use this for
    /// segment boundaries; `isSpeech(_:)` is the immediate, attack-friendly gate.
    public var isConfirmedSpeech: Bool { confirmed }

    public init(settings: Settings = Settings()) {
        self.settings = settings
        noiseRMS = settings.absoluteFloor * 0.6
    }

    /// Per-frame measured energy. Exposed for tests and AGC diagnostics.
    public static func rms(_ frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        var sum: Float = 0
        for value in frame where value.isFinite { sum += value * value }
        return (sum / Float(frame.count)).squareRoot()
    }

    /// Zero-crossings divided by frame length. NaN/Inf count as zero crossings
    /// so a broken device frame cannot be mistaken for clean voiced speech.
    public static func zeroCrossingRate(_ frame: [Float]) -> Float {
        guard frame.count > 1 else { return 0 }
        var crossings = 0
        var previous = frame[0]
        for index in 1..<frame.count {
            let current = frame[index]
            if !current.isFinite || !previous.isFinite { crossings += 1; previous = current; continue }
            if (current >= 0) != (previous >= 0) { crossings += 1 }
            previous = current
        }
        return Float(crossings) / Float(frame.count - 1)
    }

    /// A 0...1 score: 0.5 at the noise multiplier, approaching 0 for noise-only
    /// frames and 1 for speech well above the floor. Monotone in frame energy.
    public func confidence(rms: Float, zcr: Float) -> Float {
        guard rms >= settings.absoluteFloor, zcr <= settings.maxZeroCrossingRate else { return 0 }
        let ratio = rms / max(noiseRMS, 1e-5)
        let exponent = max(-30, min(30, 3.2 * (ratio - settings.noiseMultiplier)))
        return 1 / (1 + exp(-exponent))
    }

    /// Feed one frame (typically 20 ms / 320 samples) and get the smoothed
    /// speech verdict. The minimum-speech rule suppresses isolated clicks; the
    /// hangover keeps quiet word endings inside the same speech run.
    public mutating func isSpeech(_ frame: [Float]) -> Bool {
        let energy = Self.rms(frame)
        let zcr = Self.zeroCrossingRate(frame)
        let score = confidence(rms: energy, zcr: zcr)
        let voiced = score >= settings.threshold

        if voiced {
            consecutiveVoiced += 1
            hangover = max(1, Int((settings.hangoverMs / settings.frameMs).rounded(.up)))
        } else if hangover > 0 {
            if !confirmed { consecutiveVoiced = 0 }
            hangover -= 1
        } else {
            consecutiveVoiced = 0
            // Learn the noise floor only while nothing is being said.
            if energy.isFinite, energy > 0, score < settings.threshold * 0.5 {
                noiseRMS += settings.noiseAdaptation * (energy - noiseRMS)
            }
        }

        let minimum = max(1, Int((settings.minSpeechMs / settings.frameMs).rounded(.up)))
        if consecutiveVoiced >= minimum { confirmed = true }
        if !voiced, hangover == 0 { confirmed = false; consecutiveVoiced = 0 }
        // Immediate attack so a word onset is never gated away; the hangover
        // carries quiet word-final consonants into the same speech run.
        return voiced || hangover > 0
    }

    /// Runs `isSpeech(_:)` over 20 ms frames of a larger block.
    public mutating func verdicts(for samples: [Float]) -> [Bool] {
        let frameLength = max(1, Int((settings.sampleRate * settings.frameMs / 1_000).rounded()))
        var result: [Bool] = []
        result.reserveCapacity((samples.count + frameLength - 1) / frameLength)
        var start = 0
        while start < samples.count {
            let end = min(start + frameLength, samples.count)
            result.append(isSpeech(Array(samples[start..<end])))
            start = end
        }
        return result
    }

    public mutating func reset() {
        noiseRMS = settings.absoluteFloor * 0.6
        consecutiveVoiced = 0
        hangover = 0
        confirmed = false
    }
}

/// HEX `splitWavAtSilences` idea: cut a long utterance at the midpoint of a
/// real silence, never inside a word, then choose the cut nearest each ideal
/// chunk boundary. Returns sample indices; a caller slices the PCM itself.
public enum SilenceChunker {
    public static func cuts(_ samples: [Float], sampleRate: Float = 16_000,
                            targetChunks: Int = 6, minSilenceMs: Float = 300) -> [Int] {
        let window = max(1, Int(sampleRate * 0.05)) // 50 ms, as in HEX Media.swift
        guard samples.count >= window * 2 else { return [] }
        let thresholdSq: Float = 0.012 * 0.012
        var silences: [(mid: Int, length: Int)] = []
        var silenceStart: Int?
        var index = 0
        while index + window <= samples.count {
            var sumSq: Float = 0
            for offset in 0..<window {
                let value = samples[index + offset]
                sumSq += value * value
            }
            let meanSq = sumSq / Float(window)
            if meanSq <= thresholdSq {
                if silenceStart == nil { silenceStart = index }
            } else if let begin = silenceStart {
                let lengthMs = Float(index - begin) / sampleRate * 1_000
                if lengthMs >= minSilenceMs { silences.append(((begin + index) / 2, index - begin)) }
                silenceStart = nil
            }
            index += window
        }

        let durationMs = Double(samples.count) / Double(sampleRate) * 1_000
        let chunks = min(6, max(2, targetChunks))
        var result: [Int] = []
        for k in 1..<chunks {
            let ideal = durationMs * Double(k) / Double(chunks)
            let candidates = silences.filter { silence in
                let ms = Double(silence.mid) / Double(sampleRate) * 1_000
                return abs(ms - ideal) <= 8_000
                    && (result.last == nil || silence.mid > (result.last ?? 0) + Int(sampleRate * 5))
                    && silence.mid < samples.count - Int(sampleRate * 5)
            }
            if let best = candidates.min(by: {
                abs(Double($0.mid) / Double(sampleRate) * 1_000 - ideal)
                    < abs(Double($1.mid) / Double(sampleRate) * 1_000 - ideal)
            }) { result.append(best.mid) }
        }
        return result.sorted()
    }
}
