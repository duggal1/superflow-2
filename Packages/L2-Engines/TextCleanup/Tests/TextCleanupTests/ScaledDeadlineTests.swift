import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

/// Production `CleanupService` scales the caller's interactive deadline by
/// token count. A 1-minute dictation must not inherit the 1.5 s short-utterance
/// budget that a direct `TextCleaner.clean(options:)` call would use.
final class ScaledDeadlineTests: XCTestCase {
    func testInteractiveDeadlineScalesWithTranscriptLength() async {
        let recorder = DeadlineRecorder()
        let service = CleanupService(cleaner: recorder)
        let longText = Array(repeating: "the quarterly revenue increased significantly across all regions", count: 10)
            .joined(separator: " ")
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        var context = TextContext(settings: settings)
        context.interactive = true
        _ = await service.clean(longText, protected: Protected(), context: context)
        let recorded = await recorder.lastDeadlineMs
        XCTAssertGreaterThan(recorded ?? 0, 1_500,
                             "long interactive transcript kept the short-utterance budget: \(String(describing: recorded))")
    }

    func testShortInteractiveTranscriptKeepsFastBudget() async {
        let recorder = DeadlineRecorder()
        let service = CleanupService(cleaner: recorder)
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        var context = TextContext(settings: settings)
        context.interactive = true
        _ = await service.clean("ship it tomorrow", protected: Protected(), context: context)
        let recorded = await recorder.lastDeadlineMs
        XCTAssertEqual(recorded, 1_500)
    }
}

private actor DeadlineRecorder: TextCleaner {
    private(set) var lastDeadlineMs: Int?
    var isReady: Bool { true }
    func countTokens(_ text: String) async -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        lastDeadlineMs = options.deadlineMs
        return CleanResult(text: text, tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 1)
    }
}
