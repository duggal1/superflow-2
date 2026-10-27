import AppKit
import Foundation
import SuperflowKernel

/// The frontmost app's real icon and name, straight from the workspace.
@MainActor
enum AppInfo {
    private static var iconCache: [String: NSImage] = [:]
    private static var nameCache: [String: String] = [:]

    static func url(for bundleID: String?) -> URL? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, let url = url(for: bundleID) else { return nil }
        if let cached = iconCache[bundleID] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 20, height: 20)
        iconCache[bundleID] = image
        return image
    }

    static func name(for bundleID: String?) -> String {
        guard let bundleID, let url = url(for: bundleID) else { return "Superflow" }
        if let cached = nameCache[bundleID] { return cached }
        let bundle = Bundle(url: url)
        let name = (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        nameCache[bundleID] = name
        return name
    }
}

enum HistoryGrouping {
    struct Day: Identifiable {
        let day: String
        let sessions: [SessionRecord]

        var id: String { day }
    }

    /// Sessions arrive newest first; grouping keeps that order and labels the
    /// two days people actually recognise.
    static func days(_ sessions: [SessionRecord], today: String, calendar: Calendar = .current) -> [Day] {
        var order: [String] = []
        var buckets: [String: [SessionRecord]] = [:]
        for session in sessions {
            let key = session.localDay
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(session)
        }
        return order.map { Day(day: $0, sessions: buckets[$0] ?? []) }
    }

    static func label(for day: String, today: String, calendar: Calendar = .current) -> String {
        if day == today { return "Today" }
        if let date = LocalDay.date(from: day, calendar: calendar),
           let yesterday = calendar.date(byAdding: .day, value: -1,
                                         to: LocalDay.date(from: today, calendar: calendar) ?? Date()),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        guard let date = LocalDay.date(from: day, calendar: calendar) else { return day }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
