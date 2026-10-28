import Foundation

/// One place that turns a date or a duration into words a person would say.
/// History uses this and nothing else: no hand-built date strings, no hardcoded
/// 12- or 24-hour clock. The locale decides.
public enum Humanize {
    /// "Just now", "12 min ago", "3:01 AM", "Yesterday, 11:42 PM", "Mon, 9:14 AM", "Oct 21",
    /// "Oct 21, 2025".
    public static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let age = now.timeIntervalSince(date)
        if age < 45 { return "Just now" }
        if age < 3600 { return "\(max(1, Int(age / 60))) min ago" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        if daysAgo(date, now, calendar) < 7 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated))), \(time)"
        }
        return date.formatted(calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year())
    }

    /// Sticky section headers: "Today", "Yesterday", "Monday", "Mon, Oct 21".
    public static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if daysAgo(date, now, calendar) < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    public static func words(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count.formatted()) words"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60
            ? "\(max(1, Int(seconds.rounded()))) sec"
            : "\(Int(seconds) / 60) min \(Int(seconds) % 60) sec"
    }

    /// Playback clock with tenths: "0:01.4".
    public static func clock(_ time: TimeInterval) -> String {
        String(format: "%d:%04.1f", Int(time) / 60, time.truncatingRemainder(dividingBy: 60))
    }

    private static func daysAgo(_ date: Date, _ now: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                to: calendar.startOfDay(for: now)).day ?? .max
    }
}
