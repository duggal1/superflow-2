import Foundation
import SuperflowKernel
import SuperflowPorts

extension RecoveryEngine {
    /// Closes the active run. Later callbacks stamped with its epoch are ignored; no journal is
    /// deleted and no session is finalized by the cancel itself.
    public func cancel() async { await sessionGate.cancel() }

    /// Rearms bookkeeping only. It creates no session, appends no segment and deletes no journal;
    /// a delayed callback from the cancelled run is fenced by the epoch this returns.
    @discardableResult
    public func rearm() async -> RecoveryEpoch { await sessionGate.rearm() }

    public func recover() async -> RecoveryReport {
        var report = RecoveryReport()
        guard let epoch = await sessionGate.begin() else {
            report.skippedBusy += 1
            report.notices.append("Recovery is already running; skipped the overlapping run.")
            return report
        }
        do {
            try await fire(.listSessions)
            let unfinished = try await repository.unfinishedSessions()
            report.scanned = unfinished.count
            for session in unfinished {
                guard await sessionGate.isActive(epoch) else { break }
                await recover(session, epoch: epoch, report: &report)
            }
            if await sessionGate.isActive(epoch) {
                await sweepOrphans(known: Set(unfinished.map(\.id)), epoch: epoch, report: &report)
            }
        } catch {
            report.failed += 1
            report.needsUserAction.append(RecoverySupport.action(
                SessionID("__recovery__"), "scan-failed", error.localizedDescription))
        }
        if await sessionGate.isActive(epoch) { await collectLedgerEvidence(report: &report) }
        await sessionGate.finish(epoch: epoch)
        return report
    }

    private func collectLedgerEvidence(report: inout RecoveryReport) async {
        if let read = try? await ledger.read() { report.integrity = read.integrity }
        if let moved = try? await ledger.quarantineDamaged() {
            report.quarantinedFiles.append(contentsOf: moved.map(\.path))
            report.integrity.quarantined += moved.count
        }
        if let temps = try? AtomicFileStore(root: stateRoot).quarantineTemps() {
            report.quarantinedFiles.append(contentsOf: temps.map(\.path))
        }
        let stale = RecoveryLock.staleEvidence(root: lockRoot)
        report.quarantinedFiles.append(contentsOf: stale.map(\.path))
    }

    func fire(_ stage: RecoveryStage) async throws {
        guard let fault else { return }
        let count = faultCounts[stage, default: 0] + 1
        faultCounts[stage] = count
        if await fault(stage, count) { throw RecoveryFault(stage: stage) }
    }

    func record(_ record: RecoveryLedgerRecord, report: inout RecoveryReport) async {
        do { _ = try await ledger.append(record) } catch {
            report.notices.append("Recovery ledger could not record \(record.kind.rawValue): \(error.localizedDescription)")
        }
    }

    /// Marks a lost sample interval explicitly in both the report and the durable ledger. Recovery
    /// never invents audio or transcript text to make a discontinuity look like continuity.
    func recordGap(_ gap: RecoveryGap, report: inout RecoveryReport) async {
        report.gaps.append(gap)
        report.notices.append("\(gap.source.label) journal lost \(gap.samples) samples at \(gap.startSample) for \(gap.sessionID.short).")
        await record(RecoveryLedgerRecord(
            id: RecoverySupport.eventID(.gapDetected, session: gap.sessionID, source: gap.source,
                                        qualifier: "\(gap.startSample)"),
            kind: .gapDetected, session: gap.sessionID.value, source: gap.source.rawValue,
            samplePosition: gap.startSample, detail: gap.reason), report: &report)
    }

    /// Journals left by a prior run whose session is already terminal. Only a finalized ledger
    /// record plus a terminal session authorize deletion; everything else is reported, kept, and
    /// left for the user. Retention settings are honored: nothing is swept when journals are kept.
    private func sweepOrphans(known: Set<SessionID>, epoch: RecoveryEpoch, report: inout RecoveryReport) async {
        do {
            try await fire(.sweepOrphans)
        } catch {
            report.failed += 1
            report.needsUserAction.append(RecoverySupport.action(
                SessionID("__recovery__"), "interrupted-orphan-sweep",
                "Recovery stopped during the orphan sweep; journals were left untouched."))
            return
        }
        guard !keepJournals else { return }
        let candidates = await journals.sessionsWithJournals()
        let records = (try? await ledger.read())?.records ?? []
        for sid in candidates where !known.contains(sid) {
            guard await sessionGate.isActive(epoch) else { return }
            let row = try? await repository.session(sid)
            let finalized = records.contains { $0.session == sid.value && $0.kind == .finalized }
            // A partial recovery deliberately keeps its journal for inspection. An explicit
            // retained marker outranks finalization here, so the sweep cannot destroy that data.
            let retained = records.contains { $0.session == sid.value && $0.kind == .journalRetained }
            guard finalized, !retained, let row, row.status == .recovered || row.status == .complete else {
                report.needsUserAction.append(RecoverySupport.action(
                    sid, "orphan-journal", "A journal exists without a verified finalized recovery. It was kept."))
                continue
            }
            let samples = await journals.sampleCount(session: sid, source: .mic)
            guard await sessionGate.isActive(epoch) else { return }
            await journals.delete(session: sid)
            await record(RecoveryLedgerRecord(
                id: RecoverySupport.eventID(.journalDiscarded, session: sid, qualifier: "orphan"),
                kind: .journalDiscarded, session: sid.value, samplePosition: samples,
                detail: "orphan from a prior finalized run"), report: &report)
            report.discarded.append(RecoveryDiscarded(
                sessionID: sid, reason: "orphan from a prior finalized recovery", samples: samples))
        }
    }
}
