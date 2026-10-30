import CoreGraphics
import Foundation

/// Verification and event-posting helpers for `TextInsertionService`. Split out
/// so the decision tree stays readable and each file stays under the 400-line
/// limit.
extension TextInsertionService {
    struct InsertionAttempt {
        var inserted: Bool
        var verified: Bool
        var posted: Bool
        var steps: [String]
    }

    /// Content first, count second: one AX round trip per signal is enough.
    func captureBaseline(_ target: (any InsertionTarget)?) async -> InsertionBaseline? {
        guard let target else { return nil }
        let value = await target.textValue()
        let range = await target.selectedRange()
        let count = value == nil ? await target.characterCount() : nil
        return InsertionBaseline(value: value, range: range, count: count)
    }

    func pasteAttempt(text: String, target: (any InsertionTarget)?,
                      options: TextInsertionOptions) async -> (attempt: InsertionAttempt, keyCode: UInt16) {
        let keyCode = await keyResolver.pasteKeyCode()
        let baseline = await captureBaseline(target)
        let primary = options.postTap
        let posted = await poster.postPaste(keyCode: keyCode, tap: primary)
        var steps = [posted ? InsertionStep.cmdvPosted : InsertionStep.cmdvFailed]
        guard posted else {
            return (InsertionAttempt(inserted: false, verified: false, posted: false, steps: steps),
                    UInt16(keyCode))
        }
        guard let baseline, baseline.isUsable else {
            // No safe baseline: the chord was posted, so accept the paste but do
            // not claim verification. Never retry here, because a second chord
            // could paste twice with no way to observe either one.
            steps.append(InsertionStep.unverifiable)
            return (InsertionAttempt(inserted: true, verified: false, posted: true, steps: steps),
                    UInt16(keyCode))
        }
        let expected = baseline.expectedValue(afterInserting: text)
        let first = await awaitContent(target: target, baseline: baseline,
                                       expected: expected, timeout: options.verifyTimeout)
        if let result = confirmed(first, steps: &steps) {
            return (result, UInt16(keyCode))
        }

        // Session-level and HID-level chords are read by different hosts. When the
        // first one produced no observable change, try the other location once.
        let alternate: CGEventTapLocation = primary == .cghidEventTap
            ? .cgSessionEventTap : .cghidEventTap
        guard await poster.postPaste(keyCode: keyCode, tap: alternate) else {
            steps.append(InsertionStep.cmdvFailed)
            return (InsertionAttempt(inserted: false, verified: false, posted: true, steps: steps),
                    UInt16(keyCode))
        }
        steps.append(InsertionStep.cmdvRetried)
        let second = await awaitContent(target: target, baseline: baseline,
                                        expected: expected, timeout: options.verifyTimeout)
        if let result = confirmed(second, steps: &steps) {
            return (result, UInt16(keyCode))
        }
        steps.append(InsertionStep.pasteNotObserved)
        return (InsertionAttempt(inserted: false, verified: false, posted: true, steps: steps),
                UInt16(keyCode))
    }

    private func confirmed(_ observation: ContentObservation,
                           steps: inout [String]) -> InsertionAttempt? {
        switch observation {
        case .exact:
            steps.append(InsertionStep.valueVerified)
            return InsertionAttempt(inserted: true, verified: true, posted: true, steps: steps)
        case .changed, .countChanged:
            steps.append(InsertionStep.verified)
            return InsertionAttempt(inserted: true, verified: true, posted: true, steps: steps)
        case .nothing:
            return nil
        }
    }

    func accessibilityAttempt(text: String, target: (any InsertionTarget)?,
                              verifyTimeout: Duration) async -> InsertionAttempt {
        guard let target else {
            return InsertionAttempt(inserted: false, verified: false, posted: false,
                                    steps: [InsertionStep.axSetFailed])
        }
        let baseline = await captureBaseline(target)
        guard await target.insertSelectedText(text) else {
            return InsertionAttempt(inserted: false, verified: false, posted: false,
                                    steps: [InsertionStep.axSetFailed])
        }
        guard let baseline, baseline.isUsable else {
            return InsertionAttempt(inserted: true, verified: false, posted: false,
                                    steps: [InsertionStep.unverifiable])
        }
        let observation = await awaitContent(target: target, baseline: baseline,
                                             expected: baseline.expectedValue(afterInserting: text),
                                             timeout: verifyTimeout)
        switch observation {
        case .exact:
            return InsertionAttempt(inserted: true, verified: true, posted: false,
                                    steps: [InsertionStep.axValueVerified])
        case .changed, .countChanged:
            return InsertionAttempt(inserted: true, verified: true, posted: false,
                                    steps: [InsertionStep.axVerified])
        case .nothing:
            return InsertionAttempt(inserted: false, verified: false, posted: false,
                                    steps: [InsertionStep.axNotObserved])
        }
    }

    func writeIfNeeded(_ text: String, enabled: Bool) async -> Bool {
        guard enabled else { return false }
        return await clipboard.writeTransient(text) != nil
    }

    func waitForModifiersReleased(timeout: Duration) async {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        let deadline = ContinuousClock.now + timeout
        while !CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty,
              ContinuousClock.now < deadline {
            await sleep(.milliseconds(10))
        }
    }

    /// Polls for the strongest available confirmation. An exact value match wins;
    /// any other value change or a count change is still a confirmed insertion.
    func awaitContent(target: (any InsertionTarget)?, baseline: InsertionBaseline,
                      expected: String?, timeout: Duration) async -> ContentObservation {
        guard let target else { return .nothing }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            await sleep(.milliseconds(40))
            if let beforeValue = baseline.value {
                if let now = await target.textValue() {
                    if now == beforeValue { continue }
                    if let expected, now == expected { return .exact }
                    return .changed
                }
            }
            if let beforeCount = baseline.count,
               let now = await target.characterCount(), now != beforeCount {
                return .countChanged
            }
        }
        return .nothing
    }
}
