import Foundation
import SuperflowKernel
import SuperflowPorts

/// Crash recovery for sessions left recording or finalizing. The public behavior and the original
/// initializer are unchanged; the added state is deliberately additive and fail-safe: the ledger,
/// lock and orphan sweep never delete audio, and every discarded journal is reported.
public actor RecoveryEngine {
    private let repository: any TranscriptRepository
    private let journals: any JournalStore
    private let recognizer: any SpeechRecognizer
    private let clock: any TimeSource
    private let keepJournals: Bool
    private let cleaner: RecoveryCleaner?
    private let ledger: RecoveryLedger
    private let stateRoot: URL
    private let lockRoot: URL
    private let budgetNs: UInt64
    private let fault: RecoveryFaultInjector?
    private var faultCounts: [RecoveryStage: Int] = [:]

    public init(repository: any TranscriptRepository, journals: any JournalStore,
                recognizer: any SpeechRecognizer, clock: any TimeSource = SystemTimeSource(),
                keepJournals: Bool = false, cleaner: RecoveryCleaner? = nil,
                stateRoot: URL? = nil, lockRoot: URL? = nil,
                recoveryBudget: Duration = .seconds(180),
                fault: RecoveryFaultInjector? = nil) {
        self.repository = repository
        self.journals = journals
        self.recognizer = recognizer
        self.clock = clock
        self.keepJournals = keepJournals
        self.cleaner = cleaner
        let state = stateRoot ?? RecoverySupport.defaultRoot("State")
        self.stateRoot = state
        self.lockRoot = lockRoot ?? RecoverySupport.defaultRoot("Locks")
        self.ledger = RecoveryLedger(root: state)
        self.budgetNs = UInt64(max(0, recoveryBudget.components.seconds)) * 1_000_000_000
            + UInt64(max(0, recoveryBudget.components.attoseconds) / 1_000_000_000)
        self.fault = fault
    }

    public func recover() async -> RecoveryReport {
        var report = RecoveryReport()
        do {
            try await fire(.listSessions)
            let unfinished = try await repository.unfinishedSessions()
            report.scanned = unfinished.count
            for session in unfinished {
                await recover(session, report: &report)
            }
            await sweepOrphans(known: Set(unfinished.map(\.id)), report: &report)
        } catch {
            report.failed += 1
            report.needsUserAction.append(RecoverySupport.action(
                SessionID("__recovery__"), "scan-failed", error.localizedDescription))
        }
        await collectLedgerEvidence(report: &report)
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

    private func fire(_ stage: RecoveryStage) async throws {
        guard let fault else { return }
        let count = faultCounts[stage, default: 0] + 1
        faultCounts[stage] = count
        if await fault(stage, count) { throw RecoveryFault(stage: stage) }
    }

    private func record(_ record: RecoveryLedgerRecord, report: inout RecoveryReport) async {
        do { _ = try await ledger.append(record) } catch {
            report.notices.append("Recovery ledger could not record \(record.kind.rawValue): \(error.localizedDescription)")
        }
    }

    private func recover(_ session: SessionRecord, report: inout RecoveryReport) async {
        let sid = session.id
        let lock = RecoveryLock(root: lockRoot, session: sid)
        do { try lock.acquire() } catch {
            report.skippedBusy += 1
            report.needsUserAction.append(RecoverySupport.action(
                sid, "concurrent-recovery", "Another recovery process holds the lock: \(error.localizedDescription)"))
            report.notices.append("Skipped \(sid.short): recovery is already running.")
            return
        }
        defer { lock.release() }
        let startNs = clock.monotonicNs()
        func checkDeadline() throws {
            guard budgetNs > 0, clock.monotonicNs() &- startNs <= budgetNs else {
                throw SuperflowError.timeout("recovery of \(sid.short)")
            }
        }

        do {
            try await fire(.acquireLock)
            try checkDeadline()
            await record(RecoveryLedgerRecord(id: RecoverySupport.eventID(.started, session: sid),
                                              kind: .started, session: sid.value,
                                              detail: session.status.rawValue), report: &report)

            try await fire(.readSegments)
            var existing: [Segment]
            do { existing = try await repository.segments(session: sid) } catch {
                report.failed += 1
                report.needsUserAction.append(RecoverySupport.action(
                    sid, "unreadable-session", "Existing transcript rows could not be read; the journal was kept."))
                report.notices.append("Could not read the interrupted session; its journal was retained.")
                return
            }

            let ledgerRecords = (try? await ledger.read())?.records ?? []
            let watermarks = RecoverySupport.watermarks(from: ledgerRecords, session: sid)
            var nextIndex = (existing.map(\.index).max() ?? -1) + 1
            var added = 0
            var replayed: Int64 = 0
            var journalSamples: Int64 = 0
            var sourceFailed = false
            let sources: [AudioSourceKind] = session.kind == .meeting ? [.mic, .system] : [.mic]

            for source in sources {
                try checkDeadline()
                try await fire(.inspectJournal)
                let total = await journals.sampleCount(session: sid, source: source)
                journalSamples = max(journalSamples, total)
                let derived = RecoverySupport.committedSamples(for: existing, source: source)
                let fromSample = min(total, max(derived, watermarks[source] ?? 0))
                guard total > fromSample else { continue }

                do {
                    try await fire(.createStream)
                    let stream = try await recognizer.makeStream(
                        profile: ModelProfile.byID(session.modelProfile).id, source: source)
                    let collector = Task { () -> (segments: [RawSegment], failed: Bool) in
                        var segments: [RawSegment] = []
                        var failed = false
                        for await event in stream.events {
                            if case .committed(let segment) = event { segments.append(segment) }
                            if case .failure = event { failed = true }
                        }
                        return (segments, failed)
                    }
                    try await fire(.replayStart)
                    var replayedSamples: Int64 = 0
                    for await chunk in await journals.replay(session: sid, source: source,
                                                             fromSample: fromSample) {
                        try checkDeadline()
                        try await fire(.replayChunk)
                        await stream.feed(chunk)
                        replayedSamples += Int64(chunk.samples.count)
                    }
                    try checkDeadline()
                    try await fire(.streamFinish)
                    await stream.finish()
                    let recovered = await collector.value
                    guard !recovered.failed else {
                        sourceFailed = true
                        report.notices.append("Recovery could not finish \(source.label) audio for \(sid.short). The journal is retained.")
                        continue
                    }
                    guard replayedSamples > 0 else {
                        sourceFailed = true
                        report.needsUserAction.append(RecoverySupport.action(
                            sid, "unreadable-journal", "\(source.label) journal reports \(total) samples but replay returned none."))
                        continue
                    }
                    replayed += total - fromSample
                    for raw in recovered.segments {
                        let segment = RecoverySupport.absolute(raw, baseSample: fromSample)
                        let row = Segment(sessionID: sid, index: nextIndex, startMs: segment.startMs,
                                          endMs: segment.endMs, speakerID: segment.speakerHint,
                                          source: source, rawText: segment.text, cleanupState: .pending)
                        guard !RecoverySupport.isDuplicate(row, in: existing) else { continue }
                        try await fire(.appendSegment)
                        do { try await repository.appendSegment(row) } catch {
                            sourceFailed = true
                            report.notices.append("Could not commit recovered \(source.label) audio for \(sid.short): \(error.localizedDescription)")
                            break
                        }
                        existing.append(row)
                        nextIndex += 1
                        added += 1
                        await record(RecoveryLedgerRecord(
                            id: RecoverySupport.eventID(.segmentAppended, session: sid, source: source,
                                                        qualifier: "\(segment.startSample)"),
                            kind: .segmentAppended, session: sid.value, source: source.rawValue,
                            samplePosition: segment.startSample, segmentIndex: row.index), report: &report)
                    }
                    // Never advance the watermark past audio that was not actually committed.
                    // Doing so would make every retry skip the lost samples permanently.
                    guard !sourceFailed else { continue }
                    await record(RecoveryLedgerRecord(
                        id: RecoverySupport.eventID(.watermark, session: sid, source: source),
                        kind: .watermark, session: sid.value, source: source.rawValue,
                        samplePosition: total), report: &report)
                } catch {
                    sourceFailed = true
                    report.notices.append("Recovery could not replay \(source.label) audio for \(sid.short): \(error.localizedDescription)")
                    if error is RecoveryFault {
                        report.needsUserAction.append(RecoverySupport.action(
                            sid, "interrupted", "Recovery stopped while replaying \(source.label); the journal was retained."))
                    }
                    if let timedOut = error as? SuperflowError, case .timeout = timedOut {
                        report.needsUserAction.append(RecoverySupport.action(
                            sid, "recovery-timeout", "\(source.label) exceeded the recovery time budget."))
                    }
                }
            }
            lock.touch()
            guard !sourceFailed else { report.failed += 1; return }

            var cleanedCount = 0
            if let cleaner {
                for index in existing.indices where !existing[index].rawText.isEmpty && existing[index].cleanupState != .cleaned {
                    try checkDeadline()
                    try await fire(.cleanSegment)
                    let segment = existing[index]
                    let cleaned = await cleaner(segment.rawText)
                    if cleaned.text != segment.rawText || cleaned.state == .cleaned {
                        do {
                            try await repository.updateCleaned(session: sid, index: segment.index,
                                                               cleaned: cleaned.text, state: cleaned.state)
                        } catch {
                            report.failed += 1
                            report.needsUserAction.append(RecoverySupport.action(
                                sid, "cleanup-write-failed", "A cleaned segment could not be saved; the journal was kept."))
                            report.notices.append("Could not save the recovered transcript; its journal was retained.")
                            return
                        }
                        existing[index].cleanedText = cleaned.text
                        existing[index].cleanupState = cleaned.state
                        if cleaned.state == .cleaned { cleanedCount += 1 }
                        await record(RecoveryLedgerRecord(
                            id: RecoverySupport.eventID(.cleaned, session: sid, qualifier: "\(segment.index)"),
                            kind: .cleaned, session: sid.value, segmentIndex: segment.index), report: &report)
                    }
                }
            }

            let duration = existing.map(\.endMs).max() ?? session.durationMs
            let words = existing.reduce(0) { $0 + wordCount($1.bestText) }
            try checkDeadline()
            try await fire(.finalize)
            do {
                try await repository.finalizeSession(sid, endedAt: clock.now(), status: .recovered,
                                                     durationMs: duration, wordCount: words,
                                                     cleanupState: cleanedCount > 0 ? .cleaned : .skipped)
            } catch {
                report.failed += 1
                report.needsUserAction.append(RecoverySupport.action(
                    sid, "finalize-failed", "The session could not be finalized; the journal was kept."))
                report.notices.append("Could not finalize recovered session \(sid.short): \(error.localizedDescription)")
                return
            }

            // The finalization is durable in the ledger *before* any journal deletion. A crash in
            // between is therefore detectable and the orphan sweep finishes the disposition.
            await record(RecoveryLedgerRecord(
                id: RecoverySupport.eventID(.finalized, session: sid), kind: .finalized,
                session: sid.value, detail: "segments=\(added)"), report: &report)
            try await fire(.recordFinalized)

            if keepJournals {
                await record(RecoveryLedgerRecord(
                    id: RecoverySupport.eventID(.journalRetained, session: sid),
                    kind: .journalRetained, session: sid.value), report: &report)
            } else {
                try await fire(.deleteJournal)
                await journals.delete(session: sid)
                await record(RecoveryLedgerRecord(
                    id: RecoverySupport.eventID(.journalDiscarded, session: sid),
                    kind: .journalDiscarded, session: sid.value,
                    samplePosition: journalSamples, detail: "verified transcript committed"), report: &report)
                report.discarded.append(RecoveryDiscarded(
                    sessionID: sid, reason: "transcript verified after successful recovery",
                    samples: journalSamples))
            }

            report.recovered += 1
            report.segmentsAdded += added
            report.segmentsCleaned += cleanedCount
            report.samplesReplayed += replayed
            let recoveredText = existing.sorted { $0.startMs < $1.startMs }.map(\.bestText)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
            if !recoveredText.isEmpty {
                report.recoveredTranscripts.append(RecoveredTranscript(sessionID: sid, text: recoveredText))
            }
            if added > 0 {
                report.notices.append("Recovered \(added) segment\(added == 1 ? "" : "s") from \(sid.short).")
            }
        } catch {
            report.failed += 1
            if error is RecoveryFault {
                report.needsUserAction.append(RecoverySupport.action(
                    sid, "interrupted", "Recovery stopped at a crash point; the journal was retained."))
            } else {
                report.needsUserAction.append(RecoverySupport.action(
                    sid, "recovery-error", error.localizedDescription))
            }
        }
    }

    /// Journals left by a prior run whose session is already terminal. Only a finalized ledger
    /// record plus a terminal session authorize deletion; everything else is reported, kept, and
    /// left for the user. Retention settings are honored: nothing is swept when journals are kept.
    private func sweepOrphans(known: Set<SessionID>, report: inout RecoveryReport) async {
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
            let row = try? await repository.session(sid)
            let finalized = records.contains { $0.session == sid.value && $0.kind == .finalized }
            guard finalized, let row, row.status == .recovered || row.status == .complete else {
                report.needsUserAction.append(RecoverySupport.action(
                    sid, "orphan-journal", "A journal exists without a verified finalized recovery. It was kept."))
                continue
            }
            let samples = await journals.sampleCount(session: sid, source: .mic)
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
