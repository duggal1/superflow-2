import Foundation
import SuperflowFeatureIsland
import SuperflowKernel
import SuperflowMeetingEngine

/// The Island's slower half: stored history, today's total, the meeting pulse and
/// the two notifications that are worth interrupting for. Everything here reads
/// the same repository the History page reads; nothing is invented.
@MainActor
extension IslandBridge {
    func refreshHistory(limit: Int = 5) async {
        guard box.storesTranscripts else {
            box.history = []
            return
        }
        let records = (try? await transcripts.sessions(kind: .dictation, query: nil,
                                                       limit: limit, offset: 0)) ?? []
        var rows: [IslandTranscript] = []
        rows.reserveCapacity(records.count)
        for record in records {
            if let transcript = await makeTranscript(record) { rows.append(transcript) }
        }
        box.history = rows
    }

    func refreshToday() async {
        guard box.storesTranscripts else {
            box.today = 0
            return
        }
        let day = LocalDay.string(for: Date())
        let stats = (try? await transcripts.dailyStats(fromDay: day, toDay: day)) ?? []
        box.today = stats.reduce(0) { $0 + $1.words }
    }

    // MARK: meeting pulse

    func startMeetingEvents(_ events: AsyncStream<MeetingEvent>, engine: MeetingEngine) {
        meetingEngine = engine
        meetingTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .level(_, let level): self.box.level(Self.meter(level))
                case .partial(_, let text):
                    self.box.partial(text)
                    self.latestText = text
                case .state(.finalizing): self.holdEnded()
                case .finished, .state(.cancelled), .state(.failed): self.cancelled()
                default: break
                }
            }
        }
    }

    func startPulses() {
        pulseTask?.cancel()
        meetingStarted = Date()
        meetingMeter = MeetingPulseTracker()
        pulseTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let started = self.meetingStarted else { return }
                if let document = await self.meetingEngine?.currentDocument {
                    let seconds = max(1, Date().timeIntervalSince(started))
                    self.box.pulse(self.meetingMeter.update(document, seconds: seconds))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPulses() {
        pulseTask?.cancel()
        pulseTask = nil
        meetingStarted = nil
        box.pulse(.empty)
    }

    // MARK: genuine notifications only

    /// A milestone is the dictation total crossing a thousand; a streak is a
    /// landmark day. Both are rate limited to one a week-ish and never repeat a
    /// value the owner has already seen.
    func announceProgress() async {
        let defaults = UserDefaults.standard
        let now = Date()
        let lastAt = defaults.double(forKey: "island.note.lastAt")
        let quiet = now.timeIntervalSince1970 - lastAt > 600

        let day = LocalDay.string(for: Date())
        let stats = (try? await transcripts.dailyStats(fromDay: day, toDay: day)) ?? []
        let today = stats.reduce(0) { $0 + $1.words }
        box.today = today

        let step = 1_000
        let reached = today / step
        let seen = defaults.integer(forKey: "island.note.lastMilestone")
        if reached > seen, quiet {
            defaults.set(reached, forKey: "island.note.lastMilestone")
            defaults.set(now.timeIntervalSince1970, forKey: "island.note.lastAt")
            box.send(.notice(.milestone(words: reached * step)))
            return
        }

        let streak = await currentStreak()
        let lastStreak = defaults.integer(forKey: "island.note.lastStreak")
        if [3, 7, 14, 30, 60, 100, 365].contains(streak), streak > lastStreak, quiet {
            defaults.set(streak, forKey: "island.note.lastStreak")
            defaults.set(now.timeIntervalSince1970, forKey: "island.note.lastAt")
            box.send(.notice(.streak(days: streak)))
        }
    }

    private func currentStreak() async -> Int {
        let calendar = Calendar.current
        let to = LocalDay.string(for: Date())
        let from = LocalDay.string(for: calendar.date(byAdding: .day, value: -366,
                                                      to: Date()) ?? Date())
        let stats = (try? await transcripts.dailyStats(fromDay: from, toDay: to)) ?? []
        let active = Set(stats.filter { $0.words > 0 }.map(\.day))
        var streak = 0
        var day = Date()
        if !active.contains(LocalDay.string(for: day)) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while active.contains(LocalDay.string(for: day)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
