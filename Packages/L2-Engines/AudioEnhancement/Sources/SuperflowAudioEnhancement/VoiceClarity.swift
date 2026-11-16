import Foundation

/// Causal pre-ASR voice chain. Removes rumble and mud, lifts presence, and
/// applies a gentle compressor so VAD and ASR receive a fuller, steadier signal.
/// Lumen-inspired biquads, adapted to 16 kHz streaming: no lookahead, no
/// allocation, no unbounded state. The true-peak ceiling stays in `AudioLeveler`.
public struct VoiceClarity: Sendable {
    private var highPass: Biquad
    private var mud: Biquad
    private var presence: Biquad
    private var envelope: Float = 0
    private let rate: Float
    private let attack: Float
    private let release: Float

    public init(sampleRate: Float = 16_000) {
        let rate = sampleRate.isFinite && sampleRate > 1_000 ? sampleRate : 16_000
        self.rate = rate
        highPass = .highpass(70, rate)
        mud = .peaking(300, q: 0.9, db: -1.2, rate)
        presence = .peaking(3_000, q: 0.9, db: 1.5, rate)
        attack = Self.coefficient(seconds: 0.010, rate: rate)
        release = Self.coefficient(seconds: 0.120, rate: rate)
    }

    private static func coefficient(seconds: Float, rate: Float) -> Float {
        exp(-1 / (seconds * rate))
    }

    /// Levels one block in place. Whole-block state is only the filter memory
    /// and the envelope follower, so word onsets keep their full transient.
    public mutating func apply(_ samples: inout [Float]) {
        guard !samples.isEmpty else { return }
        for index in samples.indices {
            let input = samples[index]
            guard input.isFinite else { samples[index] = 0; continue }
            var value = highPass.run(input)
            value = mud.run(value)
            value = presence.run(value)
            let magnitude = abs(value)
            envelope = magnitude > envelope
                ? magnitude + attack * (envelope - magnitude)
                : magnitude + release * (envelope - magnitude)
            // -24 dBFS threshold, 2:1, capped at 2 dB: firm enough to steady
            // headphones, too gentle to flatten speech or pump the noise floor.
            let over = 20 * log10(envelope + 1e-6) + 24
            let reduction = min(2, max(0, over * 0.5))
            samples[index] = value * pow(10, -reduction / 20)
        }
    }

    public mutating func reset() {
        highPass = .highpass(70, rate)
        mud = .peaking(300, q: 0.9, db: -1.2, rate)
        presence = .peaking(3_000, q: 0.9, db: 1.5, rate)
        envelope = 0
    }
}

private struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    mutating func run(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return abs(y) < 1e-20 ? 0 : y
    }

    static func highpass(_ frequency: Float, _ rate: Float) -> Biquad {
        let w = 2 * Float.pi * frequency / rate
        let cosine = cos(w), alpha = sin(w) / (2 * Float(0.7071))
        let a0 = 1 + alpha
        return Biquad(b0: ((1 + cosine) / 2) / a0, b1: -(1 + cosine) / a0,
                      b2: ((1 + cosine) / 2) / a0, a1: -2 * cosine / a0, a2: (1 - alpha) / a0)
    }

    static func peaking(_ frequency: Float, q: Float, db: Float, _ rate: Float) -> Biquad {
        let a = pow(10, db / 40)
        let w = 2 * Float.pi * frequency / rate
        let cosine = cos(w), alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha / a
        return Biquad(b0: (1 + alpha * a) / a0, b1: -2 * cosine / a0,
                      b2: (1 - alpha * a) / a0, a1: -2 * cosine / a0, a2: (1 - alpha / a) / a0)
    }
}
