import XCTest
import SuperflowKernel

final class ASRBenchmarkTests: XCTestCase {
    private func measurement(_ device: String = "test-device") -> ASRBenchmarkMeasurement {
        ASRBenchmarkMeasurement(firstPartialMs: 200, finalizationMs: 150,
                                realtimeFactor: 0.5, peakMemoryBytes: 100_000_000,
                                device: device, runtime: "test-runtime", modelID: "test-model")
    }

    private var exact: [ASRBenchmarkSample] {
        [
            .init(category: .general, reference: "the door is open", transcript: "the door is open"),
            .init(category: .technical, reference: "Next.js", transcript: "Next.js"),
            .init(category: .numbers, reference: "4.5", transcript: "4.5"),
            .init(category: .names, reference: "Meredith", transcript: "Meredith"),
        ]
    }

    func testExactMeasuredCorpusScoresOneHundred() throws {
        let result = try XCTUnwrap(ASRBenchmarkEvaluator.evaluate(exact, measurement: measurement()))
        XCTAssertEqual(result.wordErrorRate, 0)
        XCTAssertEqual(result.intelligenceScore, 100)
        XCTAssertEqual(result.technicalAccuracy, 1)
        XCTAssertEqual(result.numberAccuracy, 1)
        XCTAssertEqual(result.nameAccuracy, 1)
        XCTAssertEqual(result.sampleCount, 4)
        XCTAssertEqual(result.referenceWordCount, 9)
    }

    func testSubstitutionReducesWordAccuracyWithoutClampingRawWER() throws {
        var samples = exact
        samples[0] = .init(category: .general, reference: "the door is open",
                           transcript: "the door is closed")
        let result = try XCTUnwrap(ASRBenchmarkEvaluator.evaluate(samples, measurement: measurement()))
        XCTAssertEqual(result.wordErrorRate, 1.0 / 9.0, accuracy: 0.00001)
        XCTAssertEqual(result.intelligenceScore, 100 - (40.0 / 9.0), accuracy: 0.00001)

        samples[0] = .init(category: .general, reference: "door",
                           transcript: "an extra sequence with many invented words")
        let bigger = try XCTUnwrap(ASRBenchmarkEvaluator.evaluate(samples, measurement: measurement()))
        XCTAssertGreaterThan(bigger.wordErrorRate, 1)
        XCTAssertGreaterThanOrEqual(bigger.intelligenceScore, 0)
    }

    func testTechnicalCasingAndNumericalPunctuationAreNotPerfectMatches() throws {
        var samples = exact
        samples[1] = .init(category: .technical, reference: "Next.js", transcript: "next.js")
        samples[2] = .init(category: .numbers, reference: "4.5", transcript: "45")
        let result = try XCTUnwrap(ASRBenchmarkEvaluator.evaluate(samples, measurement: measurement()))
        XCTAssertEqual(result.technicalAccuracy, 0)
        XCTAssertEqual(result.numberAccuracy, 0)
        XCTAssertLessThan(result.intelligenceScore, 100)
    }

    func testMissingCategoriesOrInvalidDeviceReadingsProduceNoScore() {
        XCTAssertNil(ASRBenchmarkEvaluator.evaluate([], measurement: measurement()))
        XCTAssertNil(ASRBenchmarkEvaluator.evaluate(exact.dropLast().map { $0 },
                                                     measurement: measurement()))
        let impossible = ASRBenchmarkMeasurement(firstPartialMs: -.infinity,
                                                  finalizationMs: 0, realtimeFactor: 0,
                                                  peakMemoryBytes: 0, device: "",
                                                  runtime: "", modelID: "")
        XCTAssertNil(ASRBenchmarkEvaluator.evaluate(exact, measurement: impossible))
        var blank = exact
        blank[0] = .init(category: .general, reference: "", transcript: "invented words")
        XCTAssertNil(ASRBenchmarkEvaluator.evaluate(blank, measurement: measurement()))
    }

    func testSameCorpusIsDeterministicAndDoesNotInventMetadata() throws {
        let first = try XCTUnwrap(ASRBenchmarkEvaluator.evaluate(exact, measurement: measurement("M1")))
        let second = try XCTUnwrap(ASRBenchmarkEvaluator.evaluate(exact, measurement: measurement("M1")))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.measurement.device, "M1")
        XCTAssertEqual(first.measurement.modelID, "test-model")
    }
}
