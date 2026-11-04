import Foundation
import SuperflowKernel

extension TextInsertionService {
    /// Observes only a small, confidently editable AX control, after a verified
    /// insertion and an explicit learning opt-in. If AX cannot report a
    /// bounded character count, do not read its value or start a watcher.
    func observeCommittedInsertion(_ inserted: String,
                                   onCorrection: @escaping @Sendable (ObservedCorrection) async -> Void) async {
        observationTask?.cancel()
        observationTask = nil
        let ownPID = await apps.selfPID()
        guard !inserted.isEmpty, inserted.utf16.count <= 512,
              let pid = await apps.frontmostPID(),
              pid != ownPID else { return }

        let inspection = await focus.inspect(pid: pid)
        guard case .editable = inspection.focus, let target = inspection.target,
              let count = await target.boundedCharacterCount(),
              count <= 512, count >= inserted.utf16.count,
              let before = await target.textValue(), before.utf16.count <= 512,
              before.range(of: inserted) != nil else { return }

        let id = UUID().uuidString
        let bundle = await apps.bundleIdentifier(pid: pid)
        observationTask = Task { [weak self] in
            await self?.pollEdit(target: target, pid: pid, initial: before,
                                 inserted: inserted, bundle: bundle,
                                 anchorID: id, onCorrection: onCorrection)
        }
    }

    private func pollEdit(target: any InsertionTarget, pid: pid_t, initial: String,
                          inserted: String, bundle: String?, anchorID: String,
                          onCorrection: @escaping @Sendable (ObservedCorrection) async -> Void) async {
        // This is a short-lived observation of one editable field, not a global
        // keystroke hook, transcript store, or background input tracker.
        for _ in 0..<40 {
            guard !Task.isCancelled else { return }
            await sleep(.milliseconds(400))
            let frontmost = await apps.frontmostPID()
            guard !Task.isCancelled, frontmost == pid else { return }
            let inspected = await focus.inspect(pid: pid)
            guard case .editable = inspected.focus,
                  let count = await target.boundedCharacterCount(), count <= 512,
                  let current = await target.textValue(), current.utf16.count <= 512 else {
                return
            }
            if current == initial { continue }
            if let correction = InsertionEditDiff.correction(
                before: initial, after: current, inserted: inserted,
                bundleID: bundle, anchorID: anchorID) {
                await onCorrection(correction)
            }
            return
        }
    }
}
