import Foundation

/// Causal AGC leveler applied after denoising and before ASR.
///
/// - Fast attack (up to target), slow release (down).
/// - Gain frozen while no speech is detected, so it never pumps the noise floor.
/// - True-peak limiter at -1 dBFS; the whole block is scaled, never scanned
///   sample-by-sample, so word starts are not clipped by the ramp.
/// - The right RMS target depends on the ASR model; it is tuned against
///   measured WER (start -20 dBFS speech RMS), not assumed.
public struct AudioLeveler: Sendable {
    public static let targetRMS: Float = 0.1 // -20 dBFS
    public static let peakLimit: Float = 0.891 // -1 dBFS
    public static let silenceRMS: Float = 0.005
    public static let maxGain: Float = 12.0
    public static let releaseStep: Float = 0.05

    /// Baseline 150% boost, always on as the default. The AGC then rides
    /// around it toward the RMS target.
    private var currentGain: Float = 1.5

    public init() {}

    /// Levels one block in place. Whole-block gain, so onset samples get full
    /// level immediately (fast attack) with no per-sample ramp clipping.
    /// O(n), preallocated state only; safe on the audio relay path.
    public mutating func level(_ samples: inout [Float]) -> Float {
        guard !samples.isEmpty else { return currentGain }
        var sumSq: Float = 0
        var peak: Float = 0
        for sample in samples {
            sumSq += sample * sample
            let magnitude = sample >= 0 ? sample : -sample
            if magnitude > peak { peak = magnitude }
        }
        let rms = (sumSq / Float(samples.count)).squareRoot()
        if rms < Self.silenceRMS {
            return currentGain // Frozen on silence.
        }
        let desired = min(Self.targetRMS / max(rms, 1e-6), Self.maxGain)
        if desired < currentGain {
            currentGain += (desired - currentGain) * Self.releaseStep
        } else {
            currentGain = desired // Fast attack.
        }
        // Limiter scales the whole block, preserving transients.
        let limited = min(currentGain, Self.peakLimit / max(peak, 1e-6))
        currentGain = limited
        guard limited != 1 else { return limited }
        for index in samples.indices {
            samples[index] *= limited
        }
        return limited
    }

    public mutating func reset() {
        currentGain = 1.5
    }

    public var gain: Float { currentGain }
}
