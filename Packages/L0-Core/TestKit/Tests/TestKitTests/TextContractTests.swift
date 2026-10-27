import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest

final class TextContractTests: XCTestCase {
    func testTextCleanerContractAgainstFake() async throws {
        try await TextCleanerContract().verify(FakeTextCleaner())
    }

    func testGrammarCheckerContractAcceptsValidUTF16Ranges() async throws {
        let lint = GrammarLint(utf16Start: 0, utf16Length: 5, kind: "spelling",
                               suggestion: "Hello")
        try await GrammarCheckerContract().verify(FakeGrammarChecker(lints: [lint]))
    }

    func testGrammarCheckerContractRejectsOutOfBoundsLint() async throws {
        let lint = GrammarLint(utf16Start: 0, utf16Length: 999, kind: "spelling",
                               suggestion: "Hello")
        do {
            try await GrammarCheckerContract().verify(FakeGrammarChecker(lints: [lint]))
            XCTFail("expected an out-of-bounds lint to fail the contract")
        } catch let failure as ContractFailure {
            XCTAssertTrue(failure.message.contains("exceeds"))
        }
    }

    func testTextInserterContractAgainstFake() async throws {
        try await TextInserterContract().verify(RecordingInserter())
    }

    func testCleanerFailureIsReported() async throws {
        let cleaner = FakeTextCleaner(.fail)
        do {
            _ = try await cleaner.clean("text", options: CleanOptions())
            XCTFail("expected clean to throw")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .modelUnavailable("fake cleaner"))
        }
    }

    func testSecureFieldInsertionIsBlockedAndDoesNotRecordText() async throws {
        let inserter = RecordingInserter()
        await inserter.setOutcome(.blockedSecureField)
        let outcome = try await inserter.insert("secret", strategy: .auto)
        XCTAssertEqual(outcome, .blockedSecureField)
        let inserted = await inserter.inserted
        XCTAssertTrue(inserted.isEmpty)
    }
}
