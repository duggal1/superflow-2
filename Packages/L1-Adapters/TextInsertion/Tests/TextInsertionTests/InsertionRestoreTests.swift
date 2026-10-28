import XCTest
@testable import SuperflowTextInsertion

final class InsertionRestoreTests: XCTestCase {
    func testInlineSchedulerRecordsDelayAndRunsAction() async {
        let scheduler = InlineRestoreScheduler()
        let box = Box(0)
        scheduler.schedule(after: .milliseconds(500)) { box.value += 1 }
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(scheduler.delays, [.milliseconds(500)])
        await scheduler.runPending()
        XCTAssertEqual(box.value, 1)
    }

    func testCancelledRestoreNeverRuns() async {
        let scheduler = InlineRestoreScheduler()
        let box = Box(0)
        let handle = scheduler.schedule(after: .milliseconds(50)) { box.value += 1 }
        handle.cancel()
        await scheduler.runPending()
        XCTAssertEqual(box.value, 0)
    }

    func testReportBuilderCarriesTagsAndDuration() {
        var mutable = InsertionReportBuilder()
        mutable.append(InsertionStep.pbWritten)
        mutable.append(InsertionStep.verified)
        let report = mutable.build(result: .inserted(method: .paste, verified: true),
                                   focus: .editable(role: "AXTextArea"), axTrusted: true,
                                   keyCode: 9, restoreScheduled: true)
        XCTAssertEqual(report.steps, [InsertionStep.pbWritten, InsertionStep.verified])
        XCTAssertGreaterThanOrEqual(report.durationMs, 0)
        XCTAssertTrue(report.clipboardRestoreScheduled)
    }

    func testStepTagsNeverContainTranscriptText() {
        let tags = [
            InsertionStep.empty, InsertionStep.axUntrusted, InsertionStep.noTarget,
            InsertionStep.focusEditable, InsertionStep.focusNotEditable, InsertionStep.focusSecure,
            InsertionStep.focusUnknown, InsertionStep.pbWriteFailed, InsertionStep.pbWritten,
            InsertionStep.secureInput, InsertionStep.cmdvPosted, InsertionStep.cmdvFailed,
            InsertionStep.verified, InsertionStep.valueVerified, InsertionStep.pasteNotObserved,
            InsertionStep.unverifiable, InsertionStep.axVerified, InsertionStep.axValueVerified,
            InsertionStep.axNotObserved, InsertionStep.axSetFailed, InsertionStep.notFrontmost,
        ]
        for tag in tags {
            XCTAssertFalse(tag.contains(" "), "step tags are single tokens: \(tag)")
            XCTAssertFalse(tag.isEmpty)
        }
    }
}
