import Foundation
import SuperflowKernel

/// Local retention sweep. Heavy clip files are moved to the Trash (recoverable)
/// rather than deleted, and the move is deferred by a short grace period so an
/// Undo can cancel it. The plan runs at launch and once a day; `Forever` reads
/// nothing from disk and expires nothing.
///
/// This is deliberately local-only: there is no sync marker, no cloud upload
/// and no telemetry — just SQLite rows, the local clips folder and the Trash.
public actor RetentionSweeper {
    public struct Configuration: Sendable {
        /// `nil` means Forever: keep everything, do no work.
        public var retentionDays: Int?
        /// How long Undo has to cancel a scheduled clip removal.
        public var removalDelay: Duration
        public var audioDirectory: URL
        public var checkIntegrityOnPass: Bool

        public init(retentionDays: Int?,
                    removalDelay: Duration = .seconds(6),
                    audioDirectory: URL = AudioArchiveLocation.directory(),
                    checkIntegrityOnPass: Bool = true) {
            self.retentionDays = retentionDays
            self.removalDelay = removalDelay
            self.audioDirectory = audioDirectory
            self.checkIntegrityOnPass = checkIntegrityOnPass
        }
    }

    public struct Report: Sendable, Equatable {
        public var removalsScheduled = 0
        public var missingClipMetadataNulled = 0
        public var orphanClipsScheduled = 0
        public var integrity: String?

        public init() {}
    }

    private enum RemovalKey: Hashable, Sendable {
        case session(SessionID)
        case orphan(String)
    }

    private let store: SQLiteStore
    private let configuration: Configuration
    private var pending: [RemovalKey: Task<Void, Never>] = [:]
    private var loopTask: Task<Void, Never>?

    public init(store: SQLiteStore, configuration: Configuration) {
        self.store = store
        self.configuration = configuration
    }

    // MARK: planning

    /// Next local midnight, or now + 24h if the calendar cannot provide one.
    public static func nextDailyDate(from date: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? date.addingTimeInterval(86_400)
    }

    /// One pass over finished, expired sessions.
    public func runPass(now: Date = Date()) async throws -> Report {
        var report = Report()
        if configuration.checkIntegrityOnPass {
            report.integrity = await integrityDescription()
        }
        guard let days = configuration.retentionDays else { return report }

        report.missingClipMetadataNulled += try await repairMissingClipMetadata()

        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let expired = try await store.sessions(expiredBefore: cutoff)
        var handledIDs: Set<String> = []
        for session in expired {
            handledIDs.insert(session.id.value)
            let clip = configuration.audioDirectory
                .appendingPathComponent("\(session.id.value).m4a")
            if FileManager.default.fileExists(atPath: clip.path) {
                schedule(.session(session.id))
                report.removalsScheduled += 1
            } else {
                // The clip is already gone: do not keep advertising audio that
                // cannot be played. Null the metadata and drop the row now —
                // there is no file to give Undo a grace period over.
                await store.clearAudio(session: session.id)
                try await store.deleteSession(session.id)
                report.missingClipMetadataNulled += 1
            }
        }

        // A crash between a trash and the row delete (or between a delete and
        // a trash) can leave an orphan clip. Reap it through the same grace
        // period rather than leaking files forever.
        if let files = try? FileManager.default.contentsOfDirectory(
            at: configuration.audioDirectory, includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "m4a" {
                let id = SessionID(file.deletingPathExtension().lastPathComponent)
                if handledIDs.contains(id.value) { continue }
                if try await store.session(id) == nil {
                    schedule(.orphan(file.lastPathComponent))
                    report.orphanClipsScheduled += 1
                }
            }
        }
        return report
    }

    /// Clears dangling audio metadata for sessions whose clip file is gone, so
    /// the UI never offers to play a recording that does not exist. Returns the
    /// number of rows repaired.
    public func repairMissingClipMetadata() async throws -> Int {
        var repaired = 0
        for id in try await store.sessionsWithAudio() {
            let clip = configuration.audioDirectory
                .appendingPathComponent("\(id.value).m4a")
            if !FileManager.default.fileExists(atPath: clip.path) {
                await store.clearAudio(session: id)
                repaired += 1
            }
        }
        return repaired
    }

    /// Launch pass: a full pass plus an integrity check of the live file.
    public func runLaunchPass() async throws -> Report {
        try await runPass()
    }

    // MARK: scheduling

    /// Starts a launch pass immediately, then a pass at each local midnight.
    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await self.runLaunchPass()
            while !Task.isCancelled {
                let wait = Self.nextDailyDate(from: Date()).timeIntervalSince(Date())
                do {
                    try await Task.sleep(for: .seconds(max(60, wait)))
                } catch {
                    return
                }
                _ = try? await self.runPass()
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        _ = cancelAllRemovals()
    }

    // MARK: Undo

    /// Undo a pending clip removal. Returns false when nothing was pending.
    public func cancelRemoval(session id: SessionID) -> Bool {
        guard pending.removeValue(forKey: .session(id)) != nil else { return false }
        return true
    }

    public func cancelRemoval(clipNamed name: String) -> Bool {
        guard pending.removeValue(forKey: .orphan(name)) != nil else { return false }
        return true
    }

    public func cancelAllRemovals() -> Int {
        let keys = Array(pending.keys)
        for key in keys { pending.removeValue(forKey: key)?.cancel() }
        return keys.count
    }

    /// Runs the effect of every pending removal now instead of waiting for the
    /// grace period. Useful for shutdown and for deterministic tests.
    public func flushPendingRemovals() async {
        let keys = Array(pending.keys)
        for key in keys { pending.removeValue(forKey: key)?.cancel() }
        for key in keys { await finalize(key: key) }
    }

    public var pendingRemovalCount: Int { pending.count }

    // MARK: internals

    private func integrityDescription() async -> String {
        let result = DatabaseIntegrity.check(databaseAt: URL(fileURLWithPath: store.path))
        switch result {
        case .healthy: return "ok"
        case .corrupted(let problems): return "corrupted (\(problems.count) problem(s))"
        case .unreadable(let message): return "unreadable: \(message)"
        }
    }

    private func schedule(_ key: RemovalKey) {
        guard pending[key] == nil else { return }
        let delay = configuration.removalDelay
        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return  // cancelled by Undo
            }
            guard let self else { return }
            await self.finalizeIfStillPending(key)
        }
        pending[key] = task
    }

    private func finalizeIfStillPending(_ key: RemovalKey) async {
        guard pending.removeValue(forKey: key) != nil else { return }
        await finalize(key: key)
    }

    private func finalize(key: RemovalKey) async {
        switch key {
        case .session(let id):
            let clip = configuration.audioDirectory
                .appendingPathComponent("\(id.value).m4a")
            // Only drop the row once the file is safely in the Trash; on
            // failure leave everything for a later pass (no silent loss).
            if trash(clip) {
                await store.clearAudio(session: id)
                try? await store.deleteSession(id)
            }
        case .orphan(let name):
            _ = trash(configuration.audioDirectory.appendingPathComponent(name))
        }
    }

    @discardableResult
    private func trash(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            return false
        }
    }
}
