import Foundation

/// Benchmarks are local evidence, never catalog claims. Samples must come
/// from the same reference corpus for every model being compared.
public enum ASRBenchmarkCategory: String, Codable, Sendable, CaseIterable {
    case general, technical, numbers, names
}

public struct ASRBenchmarkSample: Sendable, Codable, Equatable {
    public let category: ASRBenchmarkCategory
    public let reference: String
    public let transcript: String

    public init(category: ASRBenchmarkCategory, reference: String, transcript: String) {
        self.category = category
        self.reference = reference
        self.transcript = transcript
    }
}

public struct ASRBenchmarkMeasurement: Sendable, Codable, Equatable {
    public let firstPartialMs: Double
    public let finalizationMs: Double
    public let realtimeFactor: Double
    public let peakMemoryBytes: Int64
    public let device: String
    public let runtime: String
    public let modelID: String

    public init(firstPartialMs: Double, finalizationMs: Double,
                realtimeFactor: Double, peakMemoryBytes: Int64,
                device: String, runtime: String, modelID: String) {
        self.firstPartialMs = firstPartialMs
        self.finalizationMs = finalizationMs
        self.realtimeFactor = realtimeFactor
        self.peakMemoryBytes = peakMemoryBytes
        self.device = device
        self.runtime = runtime
        self.modelID = modelID
    }

    public var isValid: Bool {
        firstPartialMs.isFinite && firstPartialMs >= 0
            && finalizationMs.isFinite && finalizationMs >= 0
            && realtimeFactor.isFinite && realtimeFactor > 0
            && peakMemoryBytes > 0
            && !device.isEmpty && !runtime.isEmpty && !modelID.isEmpty
    }
}

/// Evaluation from an actual same-device, same-corpus ASR run. A score cannot
/// exist without measured transcripts, timings, memory, and each category.
public struct ASRBenchmarkResult: Sendable, Codable, Equatable {
    public let wordErrorRate: Double
    public let technicalAccuracy: Double
    public let numberAccuracy: Double
    public let nameAccuracy: Double
    /// Product-design weights, not an empirical probability of correctness:
    /// overall WER accuracy 40%, technical 30%, numbers 15%, names 15%.
    public let intelligenceScore: Double
    public let referenceWordCount: Int
    public let sampleCount: Int
    public let measurement: ASRBenchmarkMeasurement
}

/// Pure evaluator. It never invents ASR outputs or supplies synthetic scores
/// to Models UI. The caller owns the recording, playback and memory probes.
public enum ASRBenchmarkEvaluator {
    public static func evaluate(_ samples: [ASRBenchmarkSample],
                                measurement: ASRBenchmarkMeasurement) -> ASRBenchmarkResult? {
        guard measurement.isValid, samples.count >= 4, samples.count <= 10_000,
              Set(samples.map(\.category)) == Set(ASRBenchmarkCategory.allCases) else {
            return nil
        }

        var referenceWords = 0
        var wordErrors = 0
        var categoryHits: [ASRBenchmarkCategory: Int] = [:]
        var categoryTotals: [ASRBenchmarkCategory: Int] = [:]
        for sample in samples {
            guard sample.reference.count <= 10_000, sample.transcript.count <= 10_000 else {
                return nil
            }
            let reference = tokens(sample.reference)
            let predicted = tokens(sample.transcript)
            guard !reference.isEmpty else { return nil }
            referenceWords += reference.count
            wordErrors += distance(reference, predicted)
            categoryTotals[sample.category, default: 0] += 1
            if sample.reference.trimmingCharacters(in: .whitespacesAndNewlines)
                == sample.transcript.trimmingCharacters(in: .whitespacesAndNewlines) {
                categoryHits[sample.category, default: 0] += 1
            }
        }
        guard referenceWords > 0 else { return nil }

        func accuracy(_ kind: ASRBenchmarkCategory) -> Double {
            Double(categoryHits[kind, default: 0]) / Double(categoryTotals[kind, default: 1])
        }

        let wer = Double(wordErrors) / Double(referenceWords)
        let wordAccuracy = max(0, 1 - wer)
        let technical = accuracy(.technical)
        let numbers = accuracy(.numbers)
        let names = accuracy(.names)
        let score = 100 * (0.4 * wordAccuracy + 0.3 * technical + 0.15 * numbers + 0.15 * names)
        return ASRBenchmarkResult(
            wordErrorRate: wer,
            technicalAccuracy: technical,
            numberAccuracy: numbers,
            nameAccuracy: names,
            intelligenceScore: min(100, max(0, score)),
            referenceWordCount: referenceWords,
            sampleCount: samples.count,
            measurement: measurement)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    /// O(min(m,n)) memory, bounded because the accepted samples have a maximum.
    private static func distance(_ lhs: [String], _ rhs: [String]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        for (i, word) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, target) in rhs.enumerated() {
                current[j + 1] = min(previous[j] + (word == target ? 0 : 1),
                                     previous[j + 1] + 1, current[j] + 1)
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
