import Foundation
import SuperflowKernel
import SuperflowPorts

public actor InMemoryRepository: TranscriptRepository {
    private var sessionsByID: [SessionID: SessionRecord] = [:]
    private var segmentsBySession: [SessionID: [Segment]] = [:]
    private var speakersBySession: [SessionID: [SpeakerRecord]] = [:]
    private var days: [String: DailyStat] = [:]

    public init() {}

    public func createSession(_ s: SessionRecord) async throws {
        sessionsByID[s.id] = s
    }

    public func renameSession(_ id: SessionID, title: String) async throws {
        sessionsByID[id]?.title = title
    }

    public func appendSegment(_ s: Segment) async throws {
        var list = segmentsBySession[s.sessionID, default: []]
        list.removeAll { $0.index == s.index }
        list.append(s)
        segmentsBySession[s.sessionID] = list.sorted { $0.index < $1.index }
    }

    public func updateCleaned(session: SessionID, index: Int, cleaned: String?, state: CleanupState) async throws {
        guard var list = segmentsBySession[session], let i = list.firstIndex(where: { $0.index == index }) else { return }
        list[i].cleanedText = cleaned
        list[i].cleanupState = state
        segmentsBySession[session] = list
    }

    public func finalizeSession(_ id: SessionID, endedAt: Date, status: SessionStatus, durationMs: Int,
                                wordCount: Int, cleanupState: CleanupState) async throws {
        guard var s = sessionsByID[id] else { return }
        s.endedAt = endedAt
        s.status = status
        s.durationMs = durationMs
        s.wordCount = wordCount
        s.cleanupState = cleanupState
        sessionsByID[id] = s
    }

    public func sessions(kind: SessionKind?, query: String?, limit: Int, offset: Int) async throws -> [SessionRecord] {
        var list = sessionsByID.values.filter { kind == nil || $0.kind == kind }
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            let matching = Set(segmentsBySession.compactMap { sid, segs -> SessionID? in
                segs.contains { $0.bestText.localizedCaseInsensitiveContains(q) } ? sid : nil
            })
            list = list.filter { matching.contains($0.id) || $0.displayTitle.localizedCaseInsensitiveContains(q) }
        }
        return Array(list.sorted { $0.startedAt > $1.startedAt }.dropFirst(max(0, offset)).prefix(max(0, limit)))
    }

    public func session(_ id: SessionID) async throws -> SessionRecord? { sessionsByID[id] }

    public func segment(session: SessionID, index: Int) async throws -> Segment? {
        segmentsBySession[session]?.first { $0.index == index }
    }

    public func segments(session: SessionID) async throws -> [Segment] { segmentsBySession[session] ?? [] }

    public func deleteSession(_ id: SessionID) async throws {
        sessionsByID[id] = nil
        segmentsBySession[id] = nil
        speakersBySession[id] = nil
    }

    public func upsertSpeaker(_ s: SpeakerRecord) async throws {
        var list = speakersBySession[s.sessionID, default: []]
        list.removeAll { $0.id == s.id }
        list.append(s)
        speakersBySession[s.sessionID] = list
    }

    public func speakers(session: SessionID) async throws -> [SpeakerRecord] { speakersBySession[session] ?? [] }

    public func renameSpeaker(session: SessionID, id: String, label: String) async throws {
        guard var list = speakersBySession[session], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].label = label
        speakersBySession[session] = list
    }

    public func dailyStats(fromDay: String, toDay: String) async throws -> [DailyStat] {
        days.values.filter { $0.day >= fromDay && $0.day <= toDay }.sorted { $0.day < $1.day }
    }

    public func addDailyStat(_ s: DailyStat) async throws {
        var d = days[s.day] ?? DailyStat(day: s.day, words: 0, audioMs: 0, sessions: 0)
        d.words += s.words
        d.audioMs += s.audioMs
        d.sessions += s.sessions
        days[s.day] = d
    }

    public func unfinishedSessions() async throws -> [SessionRecord] {
        sessionsByID.values.filter { $0.status == .recording || $0.status == .finalizing }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func purge(olderThan: Date) async throws -> Int {
        let ids = sessionsByID.values.filter {
            $0.startedAt < olderThan && $0.status != .recording && $0.status != .finalizing
        }.map(\.id)
        for id in ids { sessionsByID[id] = nil; segmentsBySession[id] = nil }
        return ids.count
    }

    public func sessionCount(kind: SessionKind?) async throws -> Int {
        sessionsByID.values.filter { kind == nil || $0.kind == kind }.count
    }

    // Test helpers
    public func allSegments() -> [Segment] { segmentsBySession.values.flatMap { $0 }.sorted { $0.index < $1.index } }
}

public actor InMemoryLibrary: LibraryRepository {
    private var lex: [LexiconEntry] = []
    private var cuts: [ShortcutEntry] = []
    public init(lexicon: [LexiconEntry] = [], shortcuts: [ShortcutEntry] = []) {
        lex = lexicon
        cuts = shortcuts
    }
    public func lexicon() async throws -> [LexiconEntry] { lex }
    public func saveLexicon(_ e: LexiconEntry) async throws {
        lex.removeAll { $0.id == e.id }
        lex.append(e)
    }
    public func deleteLexicon(id: String) async throws { lex.removeAll { $0.id == id } }
    public func shortcuts() async throws -> [ShortcutEntry] { cuts }
    public func saveShortcut(_ e: ShortcutEntry) async throws {
        cuts.removeAll { $0.id == e.id }
        cuts.append(e)
    }
    public func deleteShortcut(id: String) async throws { cuts.removeAll { $0.id == id } }
}

public actor InMemorySettings: SettingsStore {
    private var value: AppSettings
    public init(_ s: AppSettings = .default) { value = s }
    public func load() async -> AppSettings { value }
    public func save(_ s: AppSettings) async { value = s }
}

public actor FakeModelProvider: ModelProvider {
    public var asrURL: URL?
    public var llmURL: URL?
    public init(asrURL: URL? = nil, llmURL: URL? = nil) {
        self.asrURL = asrURL
        self.llmURL = llmURL
    }
    public func setASRURL(_ url: URL?) { asrURL = url }
    public func setLLMURL(_ url: URL?) { llmURL = url }
    public func localURL(for profileID: String) async -> URL? { asrURL }
    public func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        guard let u = asrURL else { throw SuperflowError.modelUnavailable(profileID) }
        return u
    }
    public func llmModelURL() async -> URL? { llmURL }
    public func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        guard let u = llmURL else { throw SuperflowError.modelUnavailable("llm") }
        return u
    }
}
