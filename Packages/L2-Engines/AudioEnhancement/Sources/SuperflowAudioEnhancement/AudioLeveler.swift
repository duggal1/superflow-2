import Foundation

/// Causal AGC leveler applied after denoising and before ASR.
///
/// Root cause fixed here: the old leveler classified any frame below an
/// absolute RMS of 0.005 (-46 dBFS) as silence and froze its gain. Real
/// headset/whisper speech sits around 0.002-0.004 RMS, so it was left quiet;
/// even when detected, a 16x ceiling could never reach the -15 dBFS target.
/// Gain now follows a VAD verdict, reaches 64x (36 dB) for whispers, and the
/// noise floor is gated between utterances so the recognizer sees a fuller,
/// cleaner signal. No lookahead, no allocation on the audio path.
public struct AudioLeveler: Sendable {
    /// -15 dBFS: streamed dictation input was too quiet for reliable VAD and
    /// ASR on headphones; the limiter below still protects against clipping.
    public static let targetRMS: Float = 0.18
    public static let peakLimit: Float = 0.891 // -1 dBFS
    /// Kept for callers that display the legacy threshold. Gating now uses the
    /// VAD plus `freezeRMS`, not this value.
    public static let silenceRMS: Float = 0.005
    /// A true digital-zero frame freezes the AGC. Whispers are far above it.
    public static let freezeRMS: Float = 0.000_05
    /// 36 dB of makeup gain: enough to lift -43 dBFS whispers to the target.
    public static let maxGain: Float = 64.0
    public static let releaseStep: Float = 0.05
    /// Non-speech energy is attenuated, never amplified.
    public static let noiseGate: Float = 0.85

    /// Baseline 150% boost, always on as the default. The AGC then rides
    /// around it toward the RMS target.
    private var currentGain: Float = 2.0
    private var detector = SpeechActivityDetector()
    /// Reused per-frame scratch so the audio path allocates only once.
    private var frameBuffer = [Float](repeating: 0, count: 320)

    public init() {}

    /// Levels one block in place, in 20 ms frames. Whole-frame gain means word
    /// onsets keep their full transient (no per-sample ramp clipping).
    /// O(n), preallocated state only; safe on the audio relay path.
    @discardableResult
    public mutating func level(_ samples: inout [Float]) -> Float {
        guard !samples.isEmpty else { return currentGain }
        let frameLength = 320 // 20 ms at 16 kHz, matching the VAD frame
        var start = 0
        var applied = currentGain
        while start < samples.count {
            let end = min(start + frameLength, samples.count)
            // Sanitise non-finite samples on every frame, not just when the
            // computed gain differs from unity, so NaNs never reach ASR.
            for index in start..<end where !samples[index].isFinite { samples[index] = 0 }
            if frameBuffer.count != end - start {
                frameBuffer = [Float](repeating: 0, count: end - start)
            }
            var sumSq: Float = 0
            var peak: Float = 0
            for index in start..<end {
                let value = samples[index]
                sumSq += value * value
                let magnitude = abs(value)
                if magnitude > peak { peak = magnitude }
                frameBuffer[index - start] = value
            }
            let rms = (sumSq / Float(end - start)).squareRoot()
            let speech = detector.isSpeech(frameBuffer) && rms > Self.freezeRMS
            // Quiet consonants and whispers may be unvoiced. Treat uncertain
            // frames as audio, not silence; keep a modest gain floor without
            // allowing broadband noise to inherit the full speech gain.
            let uncertain = !speech && rms >= Self.freezeRMS && rms < 0.003

            let gain: Float
            if speech {
                let desired = min(Self.targetRMS / max(rms, 1e-6), Self.maxGain)
                if desired < currentGain {
                    currentGain += (desired - currentGain) * Self.releaseStep
                } else {
                    currentGain = desired // Fast attack.
                }
                gain = currentGain
            } else {
                // Frozen on silence/noise. Gate non-speech relative to unity,
                // never to the accumulated speech gain, so a loud utterance
                // cannot pump the noise floor afterwards.
                gain = uncertain ? min(currentGain, 2) : (rms > Self.freezeRMS
                    ? min(currentGain, 1) * Self.noiseGate : 1)
            }
            let limited = min(gain, Self.peakLimit / max(peak, 1e-6))
            for index in start..<end { samples[index] *= limited }
            applied = limited
            start = end
        }
        return applied
    }

    public mutating func reset() {
        currentGain = 2.0
        detector.reset()
    }

    public var gain: Float { currentGain }

    /// Whether the most recent frame belonged to a confirmed speech run.
    public var isInSpeech: Bool { detector.isConfirmedSpeech }
}
