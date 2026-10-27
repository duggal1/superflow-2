import Foundation
import SuperflowKernel
import SuperflowPorts

/// On launch, scans sessions left recording or finalizing, re-feeds journaled audio that has no
/// committed transcript through ASR, optionally re-cleans committed raw segments, and marks the
/// session recovered. A failure leaves the journal intact so the next launch can retry.
public actor RecoveryEngine {
    private let repository: any TranscriptRepository
    private let journals: any JournalStore
    private let recognizer: any SpeechRecognizer
    private let clock: any TimeSource
    private let keepJournals: Bool
    private let cleaner: RecoveryCleaner?

    public init(repository: any TranscriptRepository, journals: any JournalStore,
                recognizer: any SpeechRecognizer, clock: any TimeSource = SystemTimeSource(),
                keepJournals: Bool = false, cleaner: RecoveryCleaner? = nil) {
        self.repository = repository
        self.journals = journals
        self.recognizer = recognizer
        self.clock = clock
        self.keepJournals = keepJournals
        self.cleaner = cleaner
    }

    public func recover() async -> RecoveryReport {
        var report = RecoveryReport()
        let unfinished: [SessionRecord]
        do {
            unfinished = try await repository.unfinishedSessions()
        } catch {
            report.notices.append("Could not list unfinished sessions: \(error.localizedDescription)")
            return report
        }
        report.scanned = unfinished.count
        for session in unfinished {
            await recover(session, report: &report)
        }
        return report
    }

    private func recover(_ session: SessionRecord, report: inout RecoveryReport) async {
        var existing = (try? await repository.segments(session: session.id)) ?? []
        var nextIndex = (existing.map(\.index).max() ?? -1) + 1
        var added = 0
        var replayed: Int64 = 0
        var sourceFailed = false
        var anySourceSucceeded = false
        let sources: [AudioSourceKind] = session.kind == .meeting ? [.mic, .system] : [.mic]

        for source in sources {
            let total = await journals.sampleCount(session: session.id, source: source)
            guard total > 0 else { continue }
            let committedSamples = existing.filter { $0.source == source }
                .map { Int64($0.endMs) * Int64(sampleRate) / 1000 }
                .max() ?? 0
            guard total > committedSamples else {
                anySourceSucceeded = true
                continue
            }

            do {
                let stream = try await recognizer.makeStream(profile: session.modelProfile, source: source)
                let collector = Task { () -> [RawSegment] in
                    var segments: [RawSegment] = []
                    for await event in stream.events {
                        if case .committed(let segment) = event { segments.append(segment) }
                    }
                    return segments
                }
                for await chunk in await journals.replay(session: session.id, source: source,
                                                         fromSample: committedSamples) {
                    await stream.feed(chunk)
                }
                await stream.finish()
                let recovered = await collector.value
                replayed += total - committedSamples
                for segment in recovered {
                    let row = Segment(sessionID: session.id, index: nextIndex, startMs: segment.startMs,
                                      endMs: segment.endMs, speakerID: segment.speakerHint,
                                      source: source, rawText: segment.text, cleanupState: .pending)
                    try await repository.appendSegment(row)
                    existing.append(row)
                    nextIndex += 1
                    added += 1
                }
                anySourceSucceeded = true
            } catch {
                sourceFailed = true
                report.notices.append("Recovery could not replay \(source.label) audio for \(session.id.short): \(error.localizedDescription)")
            }
        }

        guard anySourceSucceeded || !sourceFailed else {
            report.failed += 1
            return
        }

        var cleanedCount = 0
        if let cleaner {
            for index in existing.indices where !existing[index].rawText.isEmpty && existing[index].cleanupState != .cleaned {
                let segment = existing[index]
                let cleaned = await cleaner(segment.rawText)
                if cleaned.text != segment.rawText || cleaned.state == .cleaned {
                    try? await repository.updateCleaned(session: session.id, index: segment.index,
                                                        cleaned: cleaned.text, state: cleaned.state)
                    existing[index].cleanedText = cleaned.text
                    existing[index].cleanupState = cleaned.state
                    if cleaned.state == .cleaned { cleanedCount += 1 }
                }
            }
        }

        let duration = existing.map(\.endMs).max() ?? session.durationMs
        let words = existing.reduce(0) { $0 + wordCount($1.bestText) }
        do {
            try await repository.finalizeSession(session.id, endedAt: clock.now(), status: .recovered,
                                                 durationMs: duration, wordCount: words,
                                                 cleanupState: cleanedCount > 0 ? .cleaned : .skipped)
        } catch {
            report.failed += 1
            report.notices.append("Could not finalize recovered session \(session.id.short): \(error.localizedDescription)")
            return
        }
        if !keepJournals { await journals.delete(session: session.id) }
        report.recovered += 1
        report.segmentsAdded += added
        report.segmentsCleaned += cleanedCount
        report.samplesReplayed += replayed
        let recoveredText = existing.sorted { $0.startMs < $1.startMs }.map(\.bestText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        if !recoveredText.isEmpty {
            report.recoveredTranscripts.append(RecoveredTranscript(sessionID: session.id, text: recoveredText))
        }
        if added > 0 {
            report.notices.append("Recovered \(added) segment\(added == 1 ? "" : "s") from \(session.id.short).")
        }
    }
}
