import Accelerate
import Foundation

/// Delay-compensated 16/48 kHz FIR pair. All processing runs off the IO thread.
struct EnhancementResampler {
    private static func taps(gain: Float) -> [Float] {
        let values = (0..<193).map { index -> Float in
            let x = Double(index - 96)
            let fc = 7_400.0 / 48_000
            let sinc = x == 0 ? 2 * fc : sin(2 * .pi * fc * x) / (.pi * x)
            let t = Double(index) / 192
            let window = 0.35875 - 0.48829 * cos(2 * .pi * t) + 0.14128 * cos(4 * .pi * t) - 0.01168 * cos(6 * .pi * t)
            return Float(sinc * window)
        }
        let scale = gain / values.reduce(0, +)
        return values.map { $0 * scale }
    }

    private let downTaps = Self.taps(gain: 1)
    private let phases: [[Float]] = {
        let padded = Self.taps(gain: 3) + [0, 0]
        return (0..<3).map { phase in (0..<65).map { padded[3 * (64 - $0) + phase] } }
    }()
    private var upCarry = [Float](repeating: 0, count: 64)
    private var downCarry = [Float](repeating: 0, count: 192)
    private var upDrop = 96
    private var downDrop = 32
    private var downIndex = 0

    mutating func upsample(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }
        let work = upCarry + input
        var output = [Float](repeating: 0, count: input.count * 3)
        work.withUnsafeBufferPointer { samples in
            guard let base = samples.baseAddress else { return }
            for i in input.indices {
                for phase in 0..<3 {
                    var value: Float = 0
                    phases[phase].withUnsafeBufferPointer { coefficients in
                        if let taps = coefficients.baseAddress { vDSP_dotpr(base + i, 1, taps, 1, &value, 65) }
                    }
                    output[i * 3 + phase] = value
                }
            }
        }
        upCarry = Array(work.suffix(64))
        let drop = min(upDrop, output.count)
        output.removeFirst(drop)
        upDrop -= drop
        return output
    }

    mutating func downsample(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }
        let work = downCarry + input
        var output: [Float] = []
        output.reserveCapacity(input.count / 3 + 1)
        var index = (3 - downIndex % 3) % 3
        work.withUnsafeBufferPointer { samples in
            downTaps.withUnsafeBufferPointer { coefficients in
                guard let base = samples.baseAddress, let taps = coefficients.baseAddress else { return }
                while index < input.count {
                    var value: Float = 0
                    vDSP_dotpr(base + index, 1, taps, 1, &value, 193)
                    output.append(value)
                    index += 3
                }
            }
        }
        downCarry = Array(work.suffix(192))
        downIndex += input.count
        let drop = min(downDrop, output.count)
        output.removeFirst(drop)
        downDrop -= drop
        return output
    }
}
