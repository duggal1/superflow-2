import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowTextCleanup

final class LongFormSafetyTests: XCTestCase {
    func testReferenceListAndTail() {
        let raw = "alright so the things we still need to do are first the text disfluency stage second the code aware path resolution third make sure streaming is forced on fourth the adaptive clipboard restore and fifth the content verification instead of just character count I think that’s everything for now"
        let segments = ListPlanner.plan(raw)
        XCTAssertEqual(segments, [.list(lead: "alright so the things we still need to do are", items: [
            "the text disfluency stage", "the code aware path resolution", "make sure streaming is forced on",
            "the adaptive clipboard restore", "the content verification instead of just character count",
        ]), .prose("I think that’s everything for now")])
    }

    func testProtectedMarkerIsContent() {
        let text = "first release second build third deploy"
        XCTAssertEqual(ListPlanner.plan(text, protected: Protected(literals: ["first release"])), [.prose(text)])
    }

    func testTwoItemsWithoutBulletMarkersStayProse() {
        XCTAssertEqual(ListPlanner.plan("first install second run"), [.prose("first install second run")])
        XCTAssertEqual(ListPlanner.plan("at first I waited a second then third place"), [.prose("at first I waited a second then third place")])
    }

    func testGuardRejectsMissingDuplicatedReorderedAndInventedContent() {
        func failure(_ input: String, _ output: String, protected: Protected = Protected()) -> CleanGuard.Failure? {
            CleanGuard.verify(input: input, protected: protected,
                              result: CleanResult(text: output, tokensIn: 0, tokensOut: 4, hitTokenCap: false, latencyMs: 0), cap: 100)
        }
        XCTAssertNotNil(failure("send alice the report today", "Send the report today."))
        XCTAssertNotNil(failure("send alice the report today", "Send Alice the report report today."))
        XCTAssertNotNil(failure("send alice the report today", "Alice send the report today."))
        XCTAssertNotNil(failure("send alice the report today", "Send Alice the secret report today."))
        XCTAssertEqual(failure("open hero.tsx", "Open hero.tsxbackup"), .protectedLost)
        XCTAssertEqual(failure("retry 500", "Retry 1500"), .protectedLost)
        XCTAssertEqual(failure("use Next.js", "Use next.js", protected: Protected(literals: ["Next.js"])), .protectedLost)
        XCTAssertNil(failure("i can't send it", "I cannot send it."))
        XCTAssertNil(failure("you know like send it", "Send it."))
    }

    func testLongFormKeepsEveryWordOnce() async {
        let input = (0..<6_000).map { "w\($0)" }.joined(separator: " ")
        let service = CleanupService(cleaner: FakeTextCleaner(.identity))
        let outcome = await service.clean(input, context: TextContext(interactive: false))
        XCTAssertEqual(outcome.text, input)
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertGreaterThan(outcome.chunks.count, 1)
    }

    func testRetryNeverDeletesLegitimateRepeatedBoundaryWords() async {
        let input = (0..<80).map { _ in "word" }.joined(separator: " ")
        let outcome = await CleanupService(cleaner: FakeTextCleaner(.fail)).clean(input, context: TextContext())
        XCTAssertEqual(outcome.text, input)
        XCTAssertEqual(outcome.state, .fallback)
    }

    func testFinalPolishPreservesProtectedCaseAndNumbers() {
        let protected = Protected(literals: ["i", "hero.tsx", "$23,450", "Next.js"])
        XCTAssertEqual(FinalPolish.text("use i and hero.tsx for $23,450 with Next.js", protected: protected),
                       "use i and hero.tsx for $23,450 with Next.js")
        XCTAssertEqual(FinalPolish.text("march 3 2026"), "march 3, 2026")
        XCTAssertEqual(FinalPolish.text("march 3 2026", protected: Protected(literals: ["march 3 2026"])), "march 3 2026")
        XCTAssertEqual(FinalPolish.text("i went home. then i left."), "I went home. Then I left.")
    }

    func testCancelledSemaphoreWaiterDoesNotLeakPermit() async throws {
        let semaphore = AsyncSemaphore(1)
        try await semaphore.acquire(priority: .background)
        let waiter = Task { try await semaphore.acquire(priority: .background) }
        await Task.yield()
        waiter.cancel()
        await semaphore.release()
        do { try await waiter.value; XCTFail("cancelled waiter succeeded") } catch is CancellationError {} catch { XCTFail("unexpected error \(error)") }
        try await semaphore.acquire(priority: .interactive)
        await semaphore.release()
    }
}
