import Foundation
import SuperflowKernel
import SuperflowPorts

/// Crash recovery for sessions left recording or finalizing. The public behavior and the original
/// initializer are unchanged; the added state is deliberately additive and fail-safe: the ledger,
/// lock and orphan sweep never delete audio, and every discarded journal is reported.
public actor RecoveryEngine {
    let repository: any TranscriptRepository
    let journals: any JournalStore
    private let recognizer: any SpeechRecognizer
    private let clock: any TimeSource
    let keepJournals: Bool
    private let cleaner: RecoveryCleaner?
    let ledger: RecoveryLedger
    let stateRoot: URL
    let lockRoot: URL
    private let budgetNs: UInt64
    /// A live recovery must never have its lock stolen on heartbeat age alone:
    /// keep the stale threshold comfortably beyond the whole recovery budget.
    private let lockStaleAfter: TimeInterval
    let fault: RecoveryFaultInjector?
    var faultCounts: [RecoveryStage: Int] = [:]
    /// Generation fence shared with late recognizer callbacks. Advancing it closes a run; a
    /// callback stamped with an older epoch can no longer mutate fresh state.
    public let epochFence = RecoveryEpochFence()
    public let sessionGate: RecoverySessionGate

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
        self.lockStaleAfter = TimeInterval(max(120, recoveryBudget.components.seconds)) + 60
        self.fault = fault
        self.sessionGate = RecoverySessionGate(fence: epochFence)
    }

    private func recover(_ session: SessionRecord, epoch: RecoveryEpoch, report: inout RecoveryReport) async {
        let sid = session.id
        let cancelledNotice = "Recovery of \(sid.short) was cancelled; late callbacks were ignored and the journal was kept."
        let lock = RecoveryLock(root: lockRoot, session: sid, staleAfter: lockStaleAfter)
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
            guard await sessionGate.isActive(epoch) else {
                report.notices.append(cancelledNotice)
                return
            }
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
            /// Degradation is tracked per lane. A lane that fails is named and retained; it never
            /// cancels the healthy lane's recovery.
            var degradedSources: Set<AudioSourceKind> = []
            var recoveredSources: Set<AudioSourceKind> = []
            let sources: [AudioSourceKind] = session.kind == .meeting ? [.mic, .system] : [.mic]

            for source in sources {
                try checkDeadline()
                guard await sessionGate.isActive(epoch) else {
                    report.notices.append(cancelledNotice)
                    return
                }
                try await fire(.inspectJournal)
                let total = await journals.sampleCount(session: sid, source: source)
                journalSamples = max(journalSamples, total)
                let derived = RecoverySupport.committedSamples(for: existing, source: source)
                let fromSample = min(total, max(derived, watermarks[source] ?? 0))
                guard total > fromSample else {
                    // Nothing new on this lane. It is healthy, just already committed.
                    recoveredSources.insert(source)
                    continue
                }

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
                    defer { collector.cancel() }
                    try await fire(.replayStart)
                    var replayedSamples: Int64 = 0
                    var expectedNext = fromSample
                    for await chunk in await journals.replay(session: sid, source: source,
                                                             fromSample: fromSample) {
                        try checkDeadline()
                        guard await sessionGate.isActive(epoch) else {
                            report.notices.append(cancelledNotice)
                            return
                        }
                        // A forward jump in the shared sample clock is lost audio. Mark it before
                        // feeding anything past it; never stitch the two sides together silently.
                        if chunk.startSample > expectedNext {
                            await recordGap(RecoveryGap(sessionID: sid, source: source,
                                                        startSample: expectedNext,
                                                        endSample: chunk.startSample,
                                                        reason: "journal discontinuity"),
                                            report: &report)
                        }
                        expectedNext = max(expectedNext, chunk.endSample)
                        try await fire(.replayChunk)
                        await stream.feed(chunk)
                        replayedSamples += Int64(chunk.samples.count)
                    }
                    if expectedNext < total {
                        await recordGap(RecoveryGap(sessionID: sid, source: source,
                                                    startSample: expectedNext, endSample: total,
                                                    reason: "journal ended before its reported sample count"),
                                        report: &report)
                    }
                    try checkDeadline()
                    guard await sessionGate.isActive(epoch) else {
                        report.notices.append(cancelledNotice)
                        return
                    }
                    try await fire(.streamFinish)
                    await stream.finish()
                    let recovered = await collector.value
                    guard await sessionGate.isActive(epoch) else {
                        report.notices.append(cancelledNotice)
                        return
                    }
                    guard !recovered.failed else {
                        degradedSources.insert(source)
                        report.notices.append("Recovery could not finish \(source.label) audio for \(sid.short). The journal is retained.")
                        report.needsUserAction.append(RecoverySupport.action(
                            sid, "source-degraded", "\(source.label) recognition failed; only that lane was degraded."))
                        continue
                    }
                    guard replayedSamples > 0 else {
                        degradedSources.insert(source)
                        report.needsUserAction.append(RecoverySupport.action(
                            sid, "unreadable-journal", "\(source.label) journal reports \(total) samples but replay returned none."))
                        continue
                    }
                    replayed += total - fromSample
                    for raw in recovered.segments {
                        // Every segment is fenced against cancel/rearm and claimed exactly once.
                        // A late recognizer callback from an abandoned run cannot append a row.
                        guard await sessionGate.isActive(epoch) else {
                            report.notices.append(cancelledNotice)
                            return
                        }
                        let segment = RecoverySupport.absolute(raw, baseSample: fromSample)
                        let row = Segment(sessionID: sid, index: nextIndex, startMs: segment.startMs,
                                          endMs: segment.endMs, speakerID: segment.speakerHint,
                                          source: source, rawText: segment.text, cleanupState: .pending)
                        guard !RecoverySupport.isDuplicate(row, in: existing) else { continue }
                        let key = "\(sid.value)|\(source.rawValue)|\(segment.startSample)|\(segment.endSample)"
                        guard await sessionGate.claimSegment(key) else { continue }
                        try await fire(.appendSegment)
                        do { try await repository.appendSegment(row) } catch {
                            degradedSources.insert(source)
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
                    // Never advance the watermark past audio that was not actually committed, and
                    // never let one lane's failure mark a healthy lane as unrecovered.
                    guard !degradedSources.contains(source) else { continue }
                    guard await sessionGate.isActive(epoch) else {
                        report.notices.append(cancelledNotice)
                        return
                    }
                    await record(RecoveryLedgerRecord(
                        id: RecoverySupport.eventID(.watermark, session: sid, source: source),
                        kind: .watermark, session: sid.value, source: source.rawValue,
                        samplePosition: total), report: &report)
                    recoveredSources.insert(source)
                } catch {
                    // A thrown fault or deadline is an interruption, not a failing dependency: on-disk
                    // state must stay exactly as a crash would leave it. Abort the whole run and keep
                    // both the journal and the unfinished session for a clean restart.
                    report.failed += 1
                    report.notices.append("Recovery could not replay \(source.label) audio for \(sid.short): \(error.localizedDescription)")
                    if error is RecoveryFault {
                        report.needsUserAction.append(RecoverySupport.action(
                            sid, "interrupted", "Recovery stopped while replaying \(source.label); the journal was retained."))
                    }
                    if let timedOut = error as? SuperflowError, case .timeout = timedOut {
                        report.needsUserAction.append(RecoverySupport.action(
                            sid, "recovery-timeout", "\(source.label) exceeded the recovery time budget."))
                    }
                    return
                }
            }
            guard await sessionGate.isActive(epoch) else {
                report.notices.append(cancelledNotice)
                return
            }
            lock.touch()

            // With no healthy lane there is no usable transcript: keep everything, report a
            // failure, and leave the session unfinished for a later attempt.
            guard !recoveredSources.isEmpty else { report.failed += 1; return }
            let fullyRecovered = degradedSources.isEmpty

            var cleanedCount = 0
            if let cleaner {
                for index in existing.indices where !existing[index].rawText.isEmpty && existing[index].cleanupState != .cleaned {
                    try checkDeadline()
                    guard await sessionGate.isActive(epoch) else {
                        report.notices.append(cancelledNotice)
                        return
                    }
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
            guard await sessionGate.isActive(epoch) else {
                report.notices.append(cancelledNotice)
                return
            }
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

            if keepJournals || !fullyRecovered {
                // A degraded lane keeps every journal on disk. The ledger's journalRetained marker
                // also stops the orphan sweep from deleting it while the session is terminal.
                await record(RecoveryLedgerRecord(
                    id: RecoverySupport.eventID(.journalRetained, session: sid),
                    kind: .journalRetained, session: sid.value,
                    detail: fullyRecovered ? "retention setting" : "degraded lanes retained for inspection"), report: &report)
                if !fullyRecovered {
                    report.degradedSources = degradedSources.sorted { $0.rawValue < $1.rawValue }
                }
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
            if !fullyRecovered {
                report.needsUserAction.append(RecoverySupport.action(
                    sid, "partial-recovery",
                    "Recovered healthy lanes only. Degraded: \(report.degradedSources.map(\.label).joined(separator: ", ")). Journal retained."))
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

}
