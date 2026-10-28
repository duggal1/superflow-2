import AppKit
import CoreGraphics
import Foundation
import OSLog
import SuperflowKernel

/// The insertion decision tree. All platform access goes through injected seams,
/// so the whole tree can be exercised without Accessibility, a keyboard, or a
/// real clipboard.
///
/// Order: secure/non-editable checks, then Accessibility first for confidently
/// editable controls, then the transient pasteboard plus synthetic Cmd+V, then
/// Accessibility as the recovery path for ambiguous containers. Insertions are
/// serialized and a pending clipboard restore is flushed before the next
/// snapshot, so two calls can never restore over each other.
public actor TextInsertionService {
    /// The prepared target is only valid for the dictation that created it.
    public static let defaultPreparedTargetTTL: Duration = .seconds(30)

    private let focus: any FocusInspecting
    let clipboard: any PasteboardAccess
    let poster: any PasteEventPosting
    let keyResolver: any PasteKeyResolving
    private let apps: any FrontmostAppProviding
    private let restoreScheduler: any RestoreScheduling
    private let secureInput: @Sendable () -> Bool
    private let axTrusted: @Sendable () -> Bool
    let sleep: @Sendable (Duration) async -> Void
    private let preparedTargetTTL: Duration

    private var preparedPID: pid_t?
    private var preparedAt: ContinuousClock.Instant?
    private var insertionInFlight = false
    private var insertionWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingRestore: PendingRestore?
    private let log = Logger(subsystem: "com.superflow.app", category: "text-insertion")

    private struct PendingRestore {
        let snapshot: PasteboardSnapshot
        let expectedChangeCount: Int
        let handle: RestoreHandle
    }

    public init(focus: any FocusInspecting,
                clipboard: any PasteboardAccess,
                poster: any PasteEventPosting,
                keyResolver: any PasteKeyResolving,
                apps: any FrontmostAppProviding,
                restoreScheduler: any RestoreScheduling,
                secureInput: @escaping @Sendable () -> Bool = { SecureInput.isActive() },
                axTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                preparedTargetTTL: Duration = TextInsertionService.defaultPreparedTargetTTL) {
        self.focus = focus
        self.clipboard = clipboard
        self.poster = poster
        self.keyResolver = keyResolver
        self.apps = apps
        self.restoreScheduler = restoreScheduler
        self.secureInput = secureInput
        self.axTrusted = axTrusted
        self.sleep = sleep
        self.preparedTargetTTL = preparedTargetTTL
    }

    /// Production wiring. `@MainActor` because the AX inspector and the TIS key
    /// resolver are main-actor types.
    @MainActor
    public static func live(pasteboard: NSPasteboard = .general) -> TextInsertionService {
        TextInsertionService(
            focus: AXFocusInspector(),
            clipboard: SystemPasteboard(pasteboard: pasteboard),
            poster: CGEventPastePoster(),
            keyResolver: LayoutPasteKeyResolver(),
            apps: WorkspaceFrontmostApps(),
            restoreScheduler: DetachedRestoreScheduler())
    }

    // MARK: - Preparation

    public func prepare(targetPID pid: pid_t) async {
        // Superflow's own window is never a dictation target. Preparing it would
        // make a later insert write into our own focused field.
        let ownPID = await apps.selfPID()
        guard pid != ownPID else {
            invalidatePreparedTarget()
            return
        }
        preparedPID = pid
        preparedAt = .now
        await focus.prepare(pid: pid)
    }

    @discardableResult
    public func prepareFrontmost() async -> pid_t? {
        let ownPID = await apps.selfPID()
        guard let pid = await apps.frontmostPID(), pid != ownPID else {
            invalidatePreparedTarget()
            return nil
        }
        await prepare(targetPID: pid)
        return pid
    }

    /// Drops the prepared target. Called when the user leaves the app that was
    /// frontmost at recording start, and available to callers on focus loss.
    public func invalidatePreparedTarget() {
        preparedPID = nil
        preparedAt = nil
    }

    public func focusState(for pid: pid_t?) async -> InsertionFocus {
        guard axTrusted() else { return .unknown(reason: "ax-not-trusted") }
        let targetPID: pid_t?
        if let pid {
            targetPID = pid
        } else {
            targetPID = await apps.frontmostPID()
        }
        guard let targetPID else { return .unknown(reason: "no-frontmost-app") }
        return await focus.inspect(pid: targetPID).focus
    }

    // MARK: - Insertion

    public func insert(_ text: String, options: TextInsertionOptions = TextInsertionOptions()) async -> TextInsertionReport {
        await acquireInsertionSlot()
        defer { releaseInsertionSlot() }
        // A previous insertion may still owe the user their original clipboard.
        // Restore it before this insertion snapshots the board.
        await flushPendingRestore()

        var report = InsertionReportBuilder()
        let trusted = axTrusted()
        var focusState: InsertionFocus = .unknown(reason: "not-inspected")
        var usedKeyCode: UInt16?

        func finish(_ result: TextInsertionResult, restore: Bool = false) -> TextInsertionReport {
            log.info("insert result=\(String(describing: result), privacy: .public) steps=\(report.steps.joined(separator: ","), privacy: .public)")
            return report.build(result: result, focus: focusState, axTrusted: trusted,
                                keyCode: usedKeyCode, restoreScheduled: restore)
        }

        guard !text.isEmpty else {
            report.append(InsertionStep.empty)
            return finish(.notInserted(.emptyText, textOnClipboard: false))
        }

        guard trusted else {
            report.append(InsertionStep.axUntrusted)
            let wrote = await clipboard.writeTransient(text) != nil
            return finish(.notInserted(.accessibilityNotTrusted, textOnClipboard: wrote))
        }

        guard let targetPID = await resolveTarget(options: options) else {
            report.append(InsertionStep.noTarget)
            let wrote = await writeIfNeeded(text, enabled: options.writeClipboardOnFailure)
            return finish(.notInserted(.noEditableTarget, textOnClipboard: wrote))
        }

        let inspection = await focus.inspect(pid: targetPID)
        focusState = inspection.focus
        switch inspection.focus {
        case .secure:
            report.append(InsertionStep.focusSecure)
            // Never insert and never overwrite the clipboard for a password field.
            return finish(.notInserted(.secureField, textOnClipboard: false))
        case .notEditable:
            report.append(InsertionStep.focusNotEditable)
            let wrote = await writeIfNeeded(text, enabled: options.writeClipboardOnFailure)
            return finish(.notInserted(.noEditableTarget, textOnClipboard: wrote))
        case .editable, .unknown:
            report.append(InsertionStep.tag(inspection.focus))
        }

        guard await apps.frontmostPID() == targetPID else {
            report.append(InsertionStep.notFrontmost)
            let wrote = await writeIfNeeded(text, enabled: options.writeClipboardOnFailure)
            return finish(.notInserted(.targetNotFrontmost, textOnClipboard: wrote))
        }

        let target = inspection.target
        let axAllowed = options.allowAccessibilityFallback || options.preferAccessibility
        let axFirst = axAllowed
            && (options.preferAccessibility
                || (options.preferAccessibilityForEditable && inspection.focus.isConfidentEditable))

        var inserted = false
        var verified = false
        var method: InsertionMethod?
        var axAttempted = false

        // Accessibility first: a confident text control needs no clipboard at all.
        if axFirst {
            axAttempted = true
            let attempt = await accessibilityAttempt(text: text, target: target,
                                                     verifyTimeout: options.verifyTimeout)
            report.append(contentsOf: attempt.steps)
            if attempt.inserted {
                return finish(.inserted(method: .accessibility, verified: attempt.verified))
            }
        }

        var snapshot: PasteboardSnapshot?
        var ourChangeCount: Int?
        var posted = false

        if options.allowPaste {
            if secureInput() {
                report.append(InsertionStep.secureInput)
            } else {
                snapshot = options.restoreClipboard
                    ? await clipboard.snapshot(maxBytes: 64 * 1024 * 1024) : nil
                guard let written = await clipboard.writeTransient(text) else {
                    report.append(InsertionStep.pbWriteFailed)
                    return finish(.notInserted(.eventPostFailed, textOnClipboard: false))
                }
                ourChangeCount = written
                report.append(InsertionStep.pbWritten)
                await waitForModifiersReleased(timeout: options.modifierReleaseTimeout)

                let attempt = await pasteAttempt(text: text, target: target, options: options)
                usedKeyCode = attempt.keyCode
                posted = attempt.attempt.posted
                report.append(contentsOf: attempt.attempt.steps)
                if attempt.attempt.inserted {
                    inserted = true
                    verified = attempt.attempt.verified
                    method = .paste
                }
            }
        }

        // Ambiguous containers paste first; Accessibility is the recovery path.
        if !inserted, !axAttempted, axAllowed {
            let attempt = await accessibilityAttempt(text: text, target: target,
                                                     verifyTimeout: options.verifyTimeout)
            report.append(contentsOf: attempt.steps)
            if attempt.inserted {
                inserted = true
                verified = attempt.verified
                method = .accessibility
            }
        }

        guard inserted, let method else {
            var onClipboard = ourChangeCount != nil
            if !onClipboard {
                onClipboard = await writeIfNeeded(text, enabled: options.writeClipboardOnFailure)
            } else if !options.writeClipboardOnFailure, let snapshot, snapshot.isComplete,
                      let expected = ourChangeCount {
                await clipboard.restore(snapshot, ifChangeCount: expected)
                onClipboard = false
            }
            let failure: InsertionFailure
            if posted {
                failure = .pasteNotObserved
            } else if options.allowPaste {
                failure = .eventPostFailed
            } else {
                failure = .accessibilityFailed
            }
            return finish(.notInserted(failure, textOnClipboard: onClipboard))
        }

        var restoreScheduled = false
        if let snapshot, let expected = ourChangeCount, snapshot.isComplete {
            // A chord that was never observed may still land, so it keeps the
            // long window. A confirmed insertion only needs a short settle.
            let delay = (posted && !verified)
                ? options.clipboardRestoreDelay
                : options.verifiedRestoreDelay
            restoreScheduled = scheduleRestore(snapshot: snapshot, expected: expected, delay: delay)
        }
        return finish(.inserted(method: method, verified: verified), restore: restoreScheduled)
    }

    // MARK: - Serialization and restore

    private func acquireInsertionSlot() async {
        if !insertionInFlight {
            insertionInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            insertionWaiters.append(continuation)
        }
    }

    private func releaseInsertionSlot() {
        if insertionWaiters.isEmpty {
            insertionInFlight = false
        } else {
            insertionWaiters.removeFirst().resume()
        }
    }

    @discardableResult
    private func scheduleRestore(snapshot: PasteboardSnapshot, expected: Int,
                                 delay: Duration) -> Bool {
        guard snapshot.isComplete else { return false }
        let clipboard = self.clipboard
        let handle = restoreScheduler.schedule(after: delay) { [weak self] in
            guard !Task.isCancelled else { return }
            await clipboard.restore(snapshot, ifChangeCount: expected)
            await self?.clearPendingRestore(expected: expected)
        }
        pendingRestore = PendingRestore(snapshot: snapshot, expectedChangeCount: expected,
                                        handle: handle)
        return true
    }

    private func flushPendingRestore() async {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        pending.handle.cancel()
        await clipboard.restore(pending.snapshot, ifChangeCount: pending.expectedChangeCount)
    }

    private func clearPendingRestore(expected: Int) {
        if pendingRestore?.expectedChangeCount == expected {
            pendingRestore = nil
        }
    }

    // MARK: - Target resolution

    private func resolveTarget(options: TextInsertionOptions) async -> pid_t? {
        if let explicit = options.targetPID { return explicit }

        let current = await apps.frontmostPID()
        let ownPID = await apps.selfPID()
        let prepared = freshPreparedPID()

        // The user moved to a different real app after recording started. Never
        // yank focus back to the old target; drop the stale preparation.
        if let prepared, let current, current != ownPID, current != prepared {
            invalidatePreparedTarget()
        }

        let target: pid_t?
        if let current, current != ownPID {
            target = current
        } else if let prepared {
            target = prepared
        } else {
            target = nil
        }
        // Consume the prepared target so a later insert can never yank focus back.
        invalidatePreparedTarget()

        if let target, target != current {
            await apps.activate(pid: target)
            _ = await waitForFrontmost(pid: target)
        }
        return target
    }

    private func freshPreparedPID() -> pid_t? {
        guard let preparedPID, let preparedAt else { return nil }
        guard ContinuousClock.now - preparedAt <= preparedTargetTTL else { return nil }
        return preparedPID
    }

    private func waitForFrontmost(pid: pid_t) async -> Bool {
        if await apps.frontmostPID() == pid { return true }
        for _ in 0..<12 {
            await sleep(.milliseconds(25))
            if await apps.frontmostPID() == pid { return true }
        }
        return false
    }
}
