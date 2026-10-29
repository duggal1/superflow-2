import SuperflowPorts

/// Owns only samples still delayed by the enhancer. Failure substitutes the raw
/// samples at those exact positions, so recording length and content are preserved.
public struct EnhancementStage: Sendable {
    private let enhancer: (any SpeechEnhancer)?
    private var active: Bool
    private var rawPending: [Float] = []
    public private(set) var failure: String?

    public init(enhancer: (any SpeechEnhancer)?, enabled: Bool) {
        self.enhancer = enhancer
        active = enabled && enhancer != nil
    }

    public mutating func push(_ samples: [Float]) async -> [Float] {
        guard active, let enhancer else { return samples }
        rawPending.append(contentsOf: samples)
        do {
            let result = try await enhancer.process(samples)
            guard result.count <= rawPending.count, result.allSatisfy(\.isFinite) else {
                return degrade("Noise suppression returned invalid audio.")
            }
            rawPending.removeFirst(result.count)
            guard rawPending.count <= 8192 else {
                // Preserve the valid prefix and substitute all remaining positions.
                return result + degrade("Noise suppression fell behind. Using microphone audio.")
            }
            return result
        } catch {
            return degrade("Noise suppression stopped. Using microphone audio: \(error.localizedDescription)")
        }
    }

    public mutating func finish() async -> [Float] {
        defer { rawPending.removeAll(keepingCapacity: true) }
        guard active, let enhancer else { return [] }
        do {
            let result = try await enhancer.finish()
            guard result.count <= rawPending.count, result.allSatisfy(\.isFinite) else {
                return degrade("Noise suppression returned an invalid tail. Using microphone audio.")
            }
            return result + rawPending.dropFirst(result.count)
        } catch {
            return degrade("Noise suppression could not finish. Using microphone audio.")
        }
    }

    private mutating func degrade(_ message: String) -> [Float] {
        active = false
        failure = message
        let raw = rawPending
        rawPending.removeAll(keepingCapacity: true)
        return raw
    }
}
