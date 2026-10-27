import AppKit
import Foundation
import SuperflowKernel
import SuperflowPorts

/// One app's share of the words. The proportion is drawn as a row fill, never a bar.
public struct AppShare: Identifiable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let words: Int

    public var id: String { bundleID }

    public init(bundleID: String, name: String, words: Int) {
        self.bundleID = bundleID
        self.name = name
        self.words = words
    }
}

/// The newest dictation as the user said it and as it landed. It doubles as the
/// example shown before there is any data, and as the golden fixture for `WordDiff`.
public struct CleanupSample: Equatable, Sendable {
    public let raw: String
    public let cleaned: String
    public var appBundleID: String?
    public var appName: String?
    public var date: Date?

    public init(raw: String, cleaned: String, appBundleID: String? = nil,
                appName: String? = nil, date: Date? = nil) {
        self.raw = raw
        self.cleaned = cleaned
        self.appBundleID = appBundleID
        self.appName = appName
        self.date = date
    }

    public var tokens: [CleanupToken] { WordDiff.tokens(raw: raw, clean: cleaned) }

    public static let example = CleanupSample(
        raw: "um the budget is uh twelve thousand dollars and we meet on tuesday at three pm",
        cleaned: "The budget is $12,000, and we meet on Tuesday at 3 PM.")
}

public struct DashboardInsights: Equatable, Sendable {
    /// Words per local hour, last 90 days, dictation only.
    public var hourly: [Int] = Array(repeating: 0, count: 24)
    /// Up to five apps, descending by words.
    public var topApps: [AppShare] = []
    /// Newest dictation of 6 to 60 words with cleaned text.
    public var latest: CleanupSample?

    public var hasData: Bool { !topApps.isEmpty }

    public init(hourly: [Int] = Array(repeating: 0, count: 24),
                topApps: [AppShare] = [],
                latest: CleanupSample? = nil) {
        self.hourly = hourly
        self.topApps = topApps
        self.latest = latest
    }

    public static let empty = DashboardInsights()
}

/// Pure aggregation, so the shape of the lower half is testable without a database.
public enum DashboardInsightsBuilder {
    public static let windowDays = 90

    public static func build(sessions: [SessionRecord],
                             latest: CleanupSample?,
                             calendar: Calendar = .current,
                             appName: (String) -> String = { AppNameLookup.name(for: $0) }) -> DashboardInsights {
        var hourly = Array(repeating: 0, count: 24)
        var wordsByApp: [String: Int] = [:]

        for session in sessions where session.kind == .dictation {
            let hour = calendar.component(.hour, from: session.startedAt)
            if hour >= 0, hour < hourly.count {
                hourly[hour] += max(0, session.wordCount)
            }
            let bundleID = session.frontmostBundleID ?? "com.superflow.unknown"
            wordsByApp[bundleID, default: 0] += max(0, session.wordCount)
        }

        let topApps = wordsByApp
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { AppShare(bundleID: $0.key, name: appName($0.key), words: $0.value) }

        return DashboardInsights(hourly: hourly, topApps: Array(topApps), latest: latest)
    }
}

/// Reads three aggregates through the existing ports. No new engine, no schema change.
@MainActor
public enum DashboardInsightsLoader {
    public static func load(repository: any TranscriptRepository,
                            now: Date = Date(),
                            calendar: Calendar = .current) async -> DashboardInsights {
        let since = calendar.date(byAdding: .day, value: -DashboardInsightsBuilder.windowDays,
                                  to: now) ?? now
        do {
            let dictation = try await repository.sessions(kind: .dictation, query: nil,
                                                          limit: 800, offset: 0)
            let recent = dictation.filter { $0.startedAt >= since }
            let candidate = dictation.first {
                (6...60).contains($0.wordCount) && $0.status == .complete
            }
            var latest: CleanupSample?
            if let candidate {
                latest = await sample(for: candidate, repository: repository)
            }
            return DashboardInsightsBuilder.build(sessions: recent, latest: latest,
                                                  calendar: calendar)
        } catch {
            return .empty
        }
    }

    private static func sample(for session: SessionRecord,
                               repository: any TranscriptRepository) async -> CleanupSample? {
        guard let segments = try? await repository.segments(session: session.id) else { return nil }
        let ordered = segments.sorted { $0.index < $1.index }
        let raw = ordered.map(\.rawText).filter { !$0.isEmpty }.joined(separator: " ")
        let cleaned = ordered.map(\.bestText).filter { !$0.isEmpty }.joined(separator: " ")
        guard !cleaned.isEmpty, cleaned != raw else { return nil }
        return CleanupSample(raw: String(raw.prefix(400)),
                             cleaned: String(cleaned.prefix(400)),
                             appBundleID: session.frontmostBundleID,
                             appName: session.frontmostBundleID.map(AppNameLookup.name(for:)),
                             date: session.startedAt)
    }
}

/// Real app names from the system. The icon comes from the same bundle id.
public enum AppNameLookup {
    public static func name(for bundleID: String) -> String {
        guard bundleID != "com.superflow.unknown" else { return "Superflow" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let bundle = Bundle(url: url)
            if let name = bundle?.infoDictionary?["CFBundleName"] as? String, !name.isEmpty {
                return name
            }
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
}
