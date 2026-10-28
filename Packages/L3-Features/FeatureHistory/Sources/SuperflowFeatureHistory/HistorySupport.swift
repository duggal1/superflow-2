import AppKit
import Foundation
import SuperflowKernel
import SuperflowUIComponents

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

/// Sticky day groups. Labels come from `Humanize`, never from a date formatter
/// in this feature.
enum HistoryGrouping {
    struct Day: Identifiable {
        let day: Date
        let sessions: [SessionRecord]

        var id: Date { day }
    }

    /// Sessions arrive newest first; grouping keeps that order.
    static func days(_ sessions: [SessionRecord], calendar: Calendar = .current) -> [Day] {
        var order: [Date] = []
        var buckets: [Date: [SessionRecord]] = [:]
        for session in sessions {
            let key = calendar.startOfDay(for: session.startedAt)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(session)
        }
        return order.map { Day(day: $0, sessions: buckets[$0] ?? []) }
    }

    static func label(for day: Date, now: Date = .now) -> String {
        Humanize.day(day, now: now)
    }
}
