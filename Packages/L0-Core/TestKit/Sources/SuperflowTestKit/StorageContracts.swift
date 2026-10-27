import Foundation
import SuperflowKernel
import SuperflowPorts

/// TranscriptRepository contract. Covers session lifecycle, segment ordering
/// and upsert, cleanup updates, search, pagination, speakers, stats, recovery
/// queries, deletion and retention purge.
public struct TranscriptRepositoryContract: Sendable {
    public init() {}

    public func verify(_ repository: any TranscriptRepository) async throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let session = SessionRecord(id: SessionID("contract-session"), kind: .dictation,
                                    startedAt: started, status: .recording,
                                    frontmostBundleID: "com.apple.TextEdit",
                                    modelProfile: "contract-profile")
        try await repository.createSession(session)
        let fetched = try await repository.session(session.id)
        try contractRequire(fetched == session, "createSession/session round trip failed")
        let missing = try await repository.session(SessionID("missing-session"))
        try contractRequire(missing == nil, "missing session returned a record")

        let second = SessionRecord(id: SessionID("contract-second"), kind: .meeting,
                                   startedAt: started.addingTimeInterval(60),
                                   status: .complete, modelProfile: "contract-profile")
        try await repository.createSession(second)

        try await repository.appendSegment(Segment(sessionID: session.id, index: 1, startMs: 10,
                                                   endMs: 20, rawText: "second contractneedle"))
        try await repository.appendSegment(Segment(sessionID: session.id, index: 0, startMs: 0,
                                                   endMs: 10, rawText: "first words"))
        var segments = try await repository.segments(session: session.id)
        try contractRequire(segments.map(\.index) == [0, 1],
                            "segments are not ordered by index: \(segments.map(\.index))")
        let oneSegment = try await repository.segment(session: session.id, index: 1)
        try contractRequire(oneSegment?.rawText == "second contractneedle",
                            "single-segment lookup returned the wrong row")
        try contractRequire(try await repository.segment(session: session.id, index: 2) == nil,
                            "single-segment lookup returned a missing row")

        var updated = segments[0]
        updated.rawText = "first words replaced"
        try await repository.appendSegment(updated)
        segments = try await repository.segments(session: session.id)
        try contractRequire(segments.count == 2, "segment append duplicated an index")
        try contractRequire(segments[0].rawText == "first words replaced",
                            "segment upsert did not replace the row")

        try await repository.updateCleaned(session: session.id, index: 0,
                                           cleaned: "First words, cleaned.", state: .cleaned)
        segments = try await repository.segments(session: session.id)
        try contractRequire(segments[0].bestText == "First words, cleaned.",
                            "updateCleaned did not become bestText")
        try contractRequire(segments[0].cleanupState == .cleaned,
                            "updateCleaned did not store the cleanup state")

        try await repository.finalizeSession(session.id,
                                             endedAt: started.addingTimeInterval(120),
                                             status: .complete, durationMs: 120_000,
                                             wordCount: 42, cleanupState: .cleaned)
        let finalized = try await repository.session(session.id)
        try contractRequire(finalized?.status == .complete, "finalize did not set status")
        try contractRequire(finalized?.wordCount == 42, "finalize did not set word count")
        try contractRequire(finalized?.cleanupState == .cleaned, "finalize did not set cleanup state")

        let found = try await repository.sessions(kind: nil, query: "contractneedle",
                                                  limit: 20, offset: 0)
        try contractRequire(found.map(\.id) == [session.id],
                            "search did not find the session by segment text")
        let wrongKind = try await repository.sessions(kind: .meeting, query: "contractneedle",
                                                      limit: 20, offset: 0)
        try contractRequire(wrongKind.isEmpty, "kind filter leaked a dictation into meetings")

        let page = try await repository.sessions(kind: nil, query: nil, limit: 1, offset: 0)
        try contractRequire(page.map(\.id) == [second.id],
                            "pagination did not return the newest session first")
        let emptyPage = try await repository.sessions(kind: nil, query: nil, limit: 0, offset: 0)
        try contractRequire(emptyPage.isEmpty, "limit 0 returned rows")

        try contractRequire(try await repository.sessionCount(kind: nil) == 2,
                            "sessionCount(all) is wrong")
        try contractRequire(try await repository.sessionCount(kind: .meeting) == 1,
                            "sessionCount(meeting) is wrong")

        try await repository.upsertSpeaker(SpeakerRecord(sessionID: session.id, id: "remote-1",
                                                         label: "Speaker 1", isSelf: false))
        try await repository.renameSpeaker(session: session.id, id: "remote-1", label: "Priya")
        let speakers = try await repository.speakers(session: session.id)
        try contractRequire(speakers.first?.label == "Priya", "speaker rename did not persist")

        try await repository.addDailyStat(DailyStat(day: "2026-01-01", words: 10,
                                                    audioMs: 1_000, sessions: 1))
        try await repository.addDailyStat(DailyStat(day: "2026-01-01", words: 5,
                                                    audioMs: 500, sessions: 1))
        let stats = try await repository.dailyStats(fromDay: "2026-01-01", toDay: "2026-01-01")
        try contractRequire(stats.count == 1 && stats[0].words == 15 && stats[0].sessions == 2,
                            "daily stats did not accumulate: \(stats)")

        let unfinished = try await repository.unfinishedSessions()
        try contractRequire(unfinished.isEmpty, "finalized session is still unfinished")

        let old = SessionRecord(id: SessionID("contract-old"), kind: .dictation,
                                startedAt: started.addingTimeInterval(-10_000),
                                status: .complete, modelProfile: "contract-profile")
        let active = SessionRecord(id: SessionID("contract-active"), kind: .dictation,
                                   startedAt: started.addingTimeInterval(-10_000),
                                   status: .recording, modelProfile: "contract-profile")
        try await repository.createSession(old)
        try await repository.createSession(active)
        let purged = try await repository.purge(olderThan: started.addingTimeInterval(-5_000))
        try contractRequire(purged == 1, "purge removed \(purged) sessions, expected 1")
        try contractRequire(try await repository.session(old.id) == nil,
                            "purge kept the expired session")
        try contractRequire(try await repository.session(active.id) != nil,
                            "purge removed an active session")

        try await repository.deleteSession(session.id)
        try contractRequire(try await repository.session(session.id) == nil,
                            "deleteSession kept the session")
        try contractRequire(try await repository.segments(session: session.id).isEmpty,
                            "deleteSession kept the segments")
    }
}

/// SettingsStore contract: default load, save/load round trip and last-write-wins.
public struct SettingsStoreContract: Sendable {
    public init() {}

    public func verify(_ store: any SettingsStore) async throws {
        let initial = await store.load()
        try contractRequire(initial == .default, "fresh settings store did not return defaults")

        var updated = AppSettings.default
        updated.displayName = "Contract"
        updated.retentionDays = 14
        updated.lineFormat.breakStyle = .newline
        await store.save(updated)
        let loaded = await store.load()
        try contractRequire(loaded == updated, "settings save/load round trip failed")

        var final = updated
        final.displayName = "Last Write"
        await store.save(final)
        let afterSecondSave = await store.load()
        try contractRequire(afterSecondSave.displayName == "Last Write",
                            "settings store did not keep the last write")
    }
}

/// ModelProvider contract for both the missing and available cases.
public struct ModelProviderContract: Sendable {
    public let asrURL: URL?
    public let llmURL: URL?

    public init(asrURL: URL? = nil, llmURL: URL? = nil) {
        self.asrURL = asrURL
        self.llmURL = llmURL
    }

    public func verify(_ provider: any ModelProvider) async throws {
        let local = await provider.localURL(for: "contract-profile")
        let available = await provider.isAvailable(profileID: "contract-profile")
        if let asrURL {
            try contractRequire(local == asrURL, "localURL did not return the configured URL")
            try contractRequire(available, "provider with a model URL reports unavailable")
            let progress = ProgressRecorder()
            let ensured = try await provider.ensure(profileID: "contract-profile",
                                                    progress: { progress.record($0) })
            try contractRequire(ensured == asrURL, "ensure returned the wrong URL")
            try contractRequire(progress.values.last == 1,
                                "ensure progress did not finish at 1")
        } else {
            try contractRequire(local == nil, "provider without a model URL returned one")
            try contractRequire(!available, "provider without a model URL reports available")
            var threw = false
            do {
                _ = try await provider.ensure(profileID: "contract-profile", progress: { _ in })
            } catch {
                threw = true
            }
            try contractRequire(threw, "ensure succeeded without a model URL")
        }

        let llm = await provider.llmModelURL()
        if let llmURL {
            try contractRequire(llm == llmURL, "llmModelURL did not return the configured URL")
            let progress = ProgressRecorder()
            let ensured = try await provider.ensureLLM(progress: { progress.record($0) })
            try contractRequire(ensured == llmURL, "ensureLLM returned the wrong URL")
            try contractRequire(progress.values.last == 1,
                                "ensureLLM progress did not finish at 1")
        } else {
            try contractRequire(llm == nil, "provider without an LLM URL returned one")
            var threw = false
            do {
                _ = try await provider.ensureLLM(progress: { _ in })
            } catch {
                threw = true
            }
            try contractRequire(threw, "ensureLLM succeeded without an LLM URL")
        }
    }
}
