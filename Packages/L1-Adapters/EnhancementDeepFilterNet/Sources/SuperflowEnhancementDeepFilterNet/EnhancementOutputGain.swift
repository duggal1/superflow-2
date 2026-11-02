struct EnhancementOutputGain: Sendable {
    static let targetGain: Float = 1.32
    static let peakLimit: Float = 0.98
    private static let releaseStep: Float = 0.2

    private var currentGain = targetGain

    mutating func apply(_ samples: [Float]) -> [Float] {
        let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
        let safeTarget = peak > 0 ? min(Self.targetGain, Self.peakLimit / peak) : Self.targetGain
        if safeTarget < currentGain {
            currentGain = safeTarget
        } else {
            currentGain += (safeTarget - currentGain) * Self.releaseStep
        }
        return samples.map { $0 * currentGain }
    }

    mutating func reset() {
        currentGain = Self.targetGain
    }
}
