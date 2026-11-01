import Foundation

/// Where an insertion lands. Kept separate so the decision tree stays readable.
extension TextInsertionService {
    /// The app the owner is looking at now wins. A prepared target is only
    /// used while it is still frontmost (or when Superflow itself is frontmost
    /// and the prepared target is the app the recording started in). An explicit
    /// target is strict only when the caller asked for it.
    func resolveTarget(options: TextInsertionOptions) async -> pid_t? {
        let current = await apps.frontmostPID()
        let ownPID = await apps.selfPID()

        if let explicit = options.targetPID {
            if !options.strictTarget, let current, current != ownPID, current != explicit {
                invalidatePreparedTarget()
                return current
            }
            invalidatePreparedTarget()
            if current != explicit {
                await apps.activate(pid: explicit)
                _ = await waitForFrontmost(pid: explicit)
            }
            return explicit
        }

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

    func freshPreparedPID() -> pid_t? {
        guard let preparedPID, let preparedAt else { return nil }
        guard ContinuousClock.now - preparedAt <= preparedTargetTTL else { return nil }
        return preparedPID
    }

    func waitForFrontmost(pid: pid_t) async -> Bool {
        if await apps.frontmostPID() == pid { return true }
        for _ in 0..<12 {
            await sleep(.milliseconds(25))
            if await apps.frontmostPID() == pid { return true }
        }
        return false
    }
}
