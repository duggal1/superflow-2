import Foundation
import XCTest
@testable import SuperflowTextInsertion

@MainActor
private struct Harness {
    let service: TextInsertionService
    let focus: FakeFocusInspector
    let target: FakeTarget
    let clipboard: FakeClipboard
    let poster: FakePoster
    let apps: FakeApps
    let scheduler: InlineRestoreScheduler
    let count: Box<Int?>
}

@MainActor
private func makeHarness(focus: InsertionFocus = .editable(role: "AXTextArea"),
                         count: Int? = 0,
                         value: String? = nil,
                         selection: (location: Int, length: Int)? = nil,
                         pasteValue: String = "",
                         trusted: Bool = true,
                         secureInput: Bool = false,
                         posterResult: Bool = true,
                         posterIncrements: Bool = true,
                          noChangePosts: Int = 0,
                         frontmost: pid_t? = 77,
                         ownPID: pid_t = 999,
                         ttl: Duration = TextInsertionService.defaultPreparedTargetTTL) -> Harness {
    let countBox = Box(count)
    let valueBox = value.map { Box(Optional($0)) }
    let target = FakeTarget(count: countBox, value: valueBox, selection: selection)
    let focusInspector = FakeFocusInspector(focus: focus, target: target)
    let clipboard = FakeClipboard()
    let poster = FakePoster(result: posterResult, increments: posterIncrements, box: countBox,
                            valueBox: valueBox, pasteValue: pasteValue,
                            noChangePosts: noChangePosts)
    let apps = FakeApps(frontmost: frontmost, ownPID: ownPID)
    let scheduler = InlineRestoreScheduler()
    let secure = Box(secureInput)
    let trustedBox = Box(trusted)
    let service = TextInsertionService(
        focus: focusInspector,
        clipboard: clipboard,
        poster: poster,
        keyResolver: FakeKeyResolver(code: 9),
        apps: apps,
        restoreScheduler: scheduler,
        secureInput: { secure.value },
        axTrusted: { trustedBox.value },
        sleep: { _ in },
        preparedTargetTTL: ttl)
    return Harness(service: service, focus: focusInspector, target: target, clipboard: clipboard,
                   poster: poster, apps: apps, scheduler: scheduler, count: countBox)
}

@MainActor
final class TextInsertionServiceTests: XCTestCase {
    func testEmptyTextDoesNotTouchTheClipboard() async {
        let harness = makeHarness()
        let report = await harness.service.insert("", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .notInserted(.emptyText, textOnClipboard: false))
        XCTAssertEqual(report.steps, [InsertionStep.empty])
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
    }

    func testUntrustedAccessibilityWritesTheClipboard() async {
        let harness = makeHarness(trusted: false)
        let report = await harness.service.insert("keep me", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .notInserted(.accessibilityNotTrusted, textOnClipboard: true))
        XCTAssertEqual(report.steps, [InsertionStep.axUntrusted])
        XCTAssertFalse(report.axTrusted)
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "keep me")
    }

    func testSecureFieldNeverWritesOrInserts() async {
        let harness = makeHarness(focus: .secure)
        let report = await harness.service.insert("secret", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .notInserted(.secureField, textOnClipboard: false))
        XCTAssertEqual(report.steps.last, InsertionStep.focusSecure)
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(harness.target.insertedTexts.isEmpty)
    }

    func testNotEditableTargetSkipsPaste() async {
        let harness = makeHarness(focus: .notEditable(reason: "role-AXButton"))
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .notInserted(.noEditableTarget, textOnClipboard: true))
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 0)
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "hello")
    }

    func testNotEditableHonoursWriteClipboardOnFailure() async {
        let harness = makeHarness(focus: .notEditable(reason: "role-AXButton"))
        var options = TextInsertionOptions()
        options.writeClipboardOnFailure = false
        let report = await harness.service.insert("hello", options: options)
        XCTAssertEqual(report.result, .notInserted(.noEditableTarget, textOnClipboard: false))
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
    }

    func testUnknownFocusStillAttemptsPaste() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"))
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: true))
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 1)
    }

    /// A host that only reads the HID stream ignores the session-level chord.
    /// The second post goes to the other tap and the same AX verification runs.
    func testUnobservedPasteRetriesAtTheAlternateTap() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXApplication"),
                                  noChangePosts: 1)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: true))
        XCTAssertEqual(report.steps, [InsertionStep.focusUnknown, InsertionStep.pbWritten,
                                      InsertionStep.cmdvPosted, InsertionStep.cmdvRetried,
                                      InsertionStep.verified])
        let taps = await harness.poster.taps
        XCTAssertEqual(taps, [.cgSessionEventTap, .cghidEventTap])
    }

    /// Without a usable baseline a second chord could paste twice, so the retry
    /// must stay disabled even when the first chord is unobservable.
    func testUnverifiablePasteDoesNotRetry() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXApplication"), count: nil)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: false))
        let taps = await harness.poster.taps
        XCTAssertEqual(taps, [.cgSessionEventTap])
    }

    func testVerifiedPasteReportsRestore() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"))
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: true))
        XCTAssertTrue(report.clipboardRestoreScheduled)
        XCTAssertEqual(report.steps, [InsertionStep.focusUnknown, InsertionStep.pbWritten,
                                      InsertionStep.cmdvPosted, InsertionStep.verified])
        XCTAssertEqual(harness.scheduler.delays, [.milliseconds(50)])
        await harness.scheduler.runPending()
        let restores = await harness.clipboard.restores
        XCTAssertEqual(restores, 1)
    }

    func testUnobservedPasteFallsBackToAccessibility() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"), posterIncrements: false)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .accessibility, verified: true))
        XCTAssertEqual(Array(report.steps.suffix(2)),
                       [InsertionStep.pasteNotObserved, InsertionStep.axVerified])
        await harness.scheduler.runPending()
        let restores = await harness.clipboard.restores
        XCTAssertEqual(restores, 1)
    }

    func testBothPathsFailLeavesTextOnClipboardAndDoesNotRestore() async {
        let harness = makeHarness(posterResult: false)
        harness.target.accepts = false
        let report = await harness.service.insert("keep me", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .notInserted(.eventPostFailed, textOnClipboard: true))
        XCTAssertEqual(report.steps.last, InsertionStep.cmdvFailed)
        XCTAssertFalse(report.clipboardRestoreScheduled)
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "keep me")
        let restores = await harness.clipboard.restores
        XCTAssertEqual(restores, 0)
    }

    func testNewerClipboardWritePreventsRestore() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"))
        _ = await harness.service.insert("hello", options: TextInsertionOptions())
        _ = await harness.clipboard.writeTransient("someone else")
        await harness.scheduler.runPending()
        let restores = await harness.clipboard.restores
        XCTAssertEqual(restores, 0)
        let text = await harness.clipboard.text
        XCTAssertEqual(text, "someone else")
    }

    func testNoTargetWhenSuperflowIsFrontmost() async {
        let harness = makeHarness(frontmost: 999, ownPID: 999)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .notInserted(.noEditableTarget, textOnClipboard: true))
        XCTAssertEqual(report.steps, [InsertionStep.noTarget])
    }

    func testPreparedTargetIsActivatedWhenSuperflowIsFrontmost() async {
        let harness = makeHarness(frontmost: 999, ownPID: 999)
        await harness.service.prepare(targetPID: 42)
        XCTAssertEqual(harness.focus.preparedPIDs, [42])

        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .accessibility, verified: true))
        let activated = await harness.apps.activated
        XCTAssertEqual(activated, [42])
        let current = await harness.apps.frontmostPID()
        XCTAssertEqual(current, 42)
    }

    func testPreparedTargetIsConsumedAfterOneInsert() async {
        let harness = makeHarness(frontmost: 999, ownPID: 999)
        await harness.service.prepare(targetPID: 42)
        _ = await harness.service.insert("first", options: TextInsertionOptions())
        await harness.apps.setFrontmost(999)

        let second = await harness.service.insert("second", options: TextInsertionOptions())
        XCTAssertEqual(second.steps, [InsertionStep.noTarget])
    }

    func testStalePreparedTargetIsIgnored() async {
        let harness = makeHarness(frontmost: 999, ownPID: 999, ttl: .zero)
        await harness.service.prepare(targetPID: 42)
        try? await Task.sleep(for: .milliseconds(2))
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.steps, [InsertionStep.noTarget])
        let activated = await harness.apps.activated
        XCTAssertTrue(activated.isEmpty)
    }

    func testSecureInputSkipsTheSyntheticChord() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"), secureInput: true)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .accessibility, verified: true))
        XCTAssertTrue(report.steps.contains(InsertionStep.secureInput))
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 0)
    }

    func testAccessibilityOnlyOptionsNeverPost() async {
        let harness = makeHarness()
        var options = TextInsertionOptions()
        options.allowPaste = false
        options.preferAccessibility = true
        let report = await harness.service.insert("hello", options: options)
        XCTAssertEqual(report.result, .inserted(method: .accessibility, verified: true))
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 0)
    }

    func testDisabledAccessibilityFallbackNeverCallsAX() async {
        let harness = makeHarness(posterResult: false)
        var options = TextInsertionOptions()
        options.allowAccessibilityFallback = false
        let report = await harness.service.insert("hello", options: options)
        XCTAssertEqual(report.result, .notInserted(.eventPostFailed, textOnClipboard: true))
        XCTAssertTrue(harness.target.insertedTexts.isEmpty)
    }

    func testTargetNotFrontmostWritesClipboard() async {
        let harness = makeHarness(frontmost: 77)
        var options = TextInsertionOptions()
        options.targetPID = 55
        let report = await harness.service.insert("hello", options: options)
        XCTAssertEqual(report.result, .notInserted(.targetNotFrontmost, textOnClipboard: true))
        XCTAssertTrue(report.steps.contains(InsertionStep.notFrontmost))
    }

    func testClipboardWriteFailureIsReportedTruthfully() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"))
        await harness.clipboard.setFailWrites(true)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .notInserted(.eventPostFailed, textOnClipboard: false))
        XCTAssertEqual(report.steps.last, InsertionStep.pbWriteFailed)
    }

    func testStepsNeverContainTranscriptText() async {
        let secret = "SUPERFLOW-SECRET-TEXT"
        let harness = makeHarness()
        let report = await harness.service.insert(secret, options: TextInsertionOptions())
        XCTAssertFalse(report.steps.contains { $0.contains(secret) })
        XCTAssertFalse(report.steps.contains { $0.contains("SUPERFLOW") })
    }

    func testFocusStateRejectsWhenUntrusted() async {
        let harness = makeHarness(trusted: false)
        let focus = await harness.service.focusState(for: nil)
        XCTAssertEqual(focus, .unknown(reason: "ax-not-trusted"))
    }

    func testPrepareFrontmostUsesTheFrontmostPID() async {
        let harness = makeHarness(frontmost: 88)
        let pid = await harness.service.prepareFrontmost()
        XCTAssertEqual(pid, 88)
        XCTAssertEqual(harness.focus.preparedPIDs, [88])
    }

    /// Superflow's own window can be frontmost when dictation starts. Preparing
    /// our own PID would later insert into Superflow's own focused field.
    func testPrepareFrontmostIgnoresSuperflowItself() async {
        let harness = makeHarness(frontmost: 999, ownPID: 999)
        let pid = await harness.service.prepareFrontmost()
        XCTAssertNil(pid)
        XCTAssertTrue(harness.focus.preparedPIDs.isEmpty)

        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.steps, [InsertionStep.noTarget])
    }

    /// An explicit self-target is just as unsafe as discovering it as frontmost.
    func testPreparingSuperflowsOwnPIDIsRejected() async {
        let harness = makeHarness(frontmost: 999, ownPID: 999)
        await harness.service.prepare(targetPID: 999)
        XCTAssertTrue(harness.focus.preparedPIDs.isEmpty)

        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.steps, [InsertionStep.noTarget])
    }

    // MARK: - Elite-path regressions (added before the upgrade)

    /// A confidently editable field must not need the clipboard at all.
    func testEditableFocusUsesAccessibilityFirstWithoutTouchingClipboard() async {
        let harness = makeHarness()
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .accessibility, verified: true))
        XCTAssertEqual(harness.target.insertedTexts, ["hello"])
        let posts = await harness.poster.posts
        XCTAssertEqual(posts, 0)
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(report.clipboardRestoreScheduled)
    }

    /// A confirmed paste only needs a short settle window, not half a second.
    func testUnverifiedPasteKeepsTheLastResortRestoreWindow() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"), count: nil)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: false))
        XCTAssertEqual(harness.scheduler.delays, [.milliseconds(500)])
    }

    /// Rapid insertions must serialize their pasteboard mutations, even though
    /// the service is reentrant while it awaits the platform.
    func testConcurrentInsertionsDoNotOverlapPasteboardWrites() async {
        let clipboard = ConcurrencyTrackingClipboard()
        let countBox = Box<Int?>(0)
        let target = FakeTarget(count: countBox)
        let focusInspector = FakeFocusInspector(focus: .unknown(reason: "role-AXGroup"), target: target)
        let poster = FakePoster(result: true, increments: true, box: countBox)
        let service = TextInsertionService(
            focus: focusInspector,
            clipboard: clipboard,
            poster: poster,
            keyResolver: FakeKeyResolver(code: 9),
            apps: FakeApps(frontmost: 77),
            restoreScheduler: InlineRestoreScheduler(),
            secureInput: { false },
            axTrusted: { true },
            sleep: { _ in })

        async let first = service.insert("first", options: TextInsertionOptions())
        async let second = service.insert("second", options: TextInsertionOptions())
        _ = await (first, second)

        let maxConcurrent = await clipboard.maxConcurrentWrites
        XCTAssertEqual(maxConcurrent, 1, "two insertions mutated the pasteboard at once")
    }

    // MARK: - Prepared target lifetime

    func testDefaultPreparedTargetTTLIsShort() {
        XCTAssertEqual(TextInsertionService.defaultPreparedTargetTTL, .seconds(30))
    }

    func testPreparedTargetIsInvalidatedWhenFrontmostAppChanges() async {
        let harness = makeHarness(frontmost: 999, ownPID: 999)
        await harness.service.prepare(targetPID: 42)
        await harness.apps.setFrontmost(55)

        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .accessibility, verified: true))
        XCTAssertEqual(harness.focus.inspectedPIDs, [55])
        let activated = await harness.apps.activated
        XCTAssertTrue(activated.isEmpty, "a stale prepared target must not steal focus")

        // The stale preparation was dropped, not merely bypassed.
        await harness.apps.setFrontmost(999)
        let second = await harness.service.insert("again", options: TextInsertionOptions())
        XCTAssertEqual(second.steps, [InsertionStep.noTarget])
    }

    func testPrepareFrontmostWithoutAFrontmostAppInvalidatesTheTarget() async {
        let harness = makeHarness(frontmost: nil)
        await harness.service.prepare(targetPID: 42)
        let pid = await harness.service.prepareFrontmost()
        XCTAssertNil(pid)

        await harness.apps.setFrontmost(999)
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.steps, [InsertionStep.noTarget])
    }

    // MARK: - Content verification

    func testAccessibilityPrimaryVerifiesWholeValueContent() async {
        let harness = makeHarness(count: 3, value: "abc", selection: (3, 0))
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .accessibility, verified: true))
        XCTAssertEqual(report.steps, [InsertionStep.focusEditable, InsertionStep.axValueVerified])
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
    }

    func testPasteVerifiesWholeValueContent() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"),
                                  count: 3, value: "abc", selection: (3, 0),
                                  pasteValue: "hello")
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: true))
        XCTAssertEqual(report.steps, [InsertionStep.focusUnknown, InsertionStep.pbWritten,
                                      InsertionStep.cmdvPosted, InsertionStep.valueVerified])
        XCTAssertEqual(harness.scheduler.delays, [.milliseconds(50)])
    }

    // MARK: - Fallback and serialization

    func testEditableFocusPastesWhenAccessibilityFirstIsDisabled() async {
        let harness = makeHarness()
        var options = TextInsertionOptions()
        options.preferAccessibilityForEditable = false
        let report = await harness.service.insert("hello", options: options)
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: true))
        XCTAssertTrue(harness.target.insertedTexts.isEmpty)
    }

    func testAccessibilityFailureFallsBackToPaste() async {
        let harness = makeHarness()
        harness.target.accepts = false
        let report = await harness.service.insert("hello", options: TextInsertionOptions())
        XCTAssertEqual(report.result, .inserted(method: .paste, verified: true))
        XCTAssertEqual(report.steps, [InsertionStep.focusEditable, InsertionStep.axSetFailed,
                                      InsertionStep.pbWritten, InsertionStep.cmdvPosted,
                                      InsertionStep.verified])
    }

    func testAccessibilityOnlyFailureReportsAccessibilityFailed() async {
        let harness = makeHarness()
        harness.target.accepts = false
        var options = TextInsertionOptions()
        options.allowPaste = false
        options.preferAccessibility = true
        options.writeClipboardOnFailure = false

        let report = await harness.service.insert("hello", options: options)
        XCTAssertEqual(report.result, .notInserted(.accessibilityFailed, textOnClipboard: false))
        XCTAssertEqual(report.steps, [InsertionStep.focusEditable, InsertionStep.axSetFailed])
        let writes = await harness.clipboard.writes
        XCTAssertEqual(writes, 0)
    }

    func testPendingRestoreIsFlushedBeforeTheNextSnapshot() async {
        let harness = makeHarness(focus: .unknown(reason: "role-AXGroup"))
        _ = await harness.clipboard.writeTransient("original")

        _ = await harness.service.insert("first", options: TextInsertionOptions())
        XCTAssertEqual(harness.scheduler.pendingCount, 1)

        _ = await harness.service.insert("second", options: TextInsertionOptions())
        // The second snapshot must see the restored board, not the first paste.
        let snapshots = await harness.clipboard.snapshotTexts
        XCTAssertEqual(snapshots, ["original", nil])
        let restores = await harness.clipboard.restores
        XCTAssertEqual(restores, 1, "the pending restore must run exactly once")
    }
}
