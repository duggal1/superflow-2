import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

/// Where it lands. Top five apps by words, real app icons, proportion as a row
/// fill behind the row. Rows are not clickable, so there is no hover and no hand.
public struct AppsCard: View {
    private let apps: [AppShare]
    @State private var shown = false

    public init(apps: [AppShare]) {
        self.apps = apps
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Where it lands", note: "Words by app, last 90 days")
            Card(padding: Space.xs) {
                VStack(spacing: Space.xxs) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        AppShareRow(app: app,
                                    share: Double(app.words) / Double(max(apps.first?.words ?? 1, 1)),
                                    shown: shown, index: index)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { shown = true }
    }
}

private struct AppShareRow: View {
    let app: AppShare
    let share: Double
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.sm) {
            AppIcon(bundleID: app.bundleID, size: 20)
            Text(app.name)
                .appType(.label)
                .foregroundStyle(Tok.text)
                .lineLimit(1)
            Spacer(minLength: Space.md)
            Text(app.words, format: .number)
                .appType(.body)
                .monospacedDigit()
                .foregroundStyle(Tok.text2)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 40)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .fill(Tok.accentSoft)
                    .frame(width: shown || reduceMotion
                           ? max(proxy.size.width * share, share > 0 ? 8 : 0)
                           : 0)
                    .animation(reduceMotion ? nil : Motion.settle.delay(Double(index) * Motion.stagger),
                               value: shown)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(app.words) words")
    }
}

/// Real app icon from the system. Falls back to the generic application icon.
public struct AppIcon: View {
    private let bundleID: String
    private let size: CGFloat
    @State private var image: NSImage?

    public init(bundleID: String, size: CGFloat = 20) {
        self.bundleID = bundleID
        self.size = size
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if image == nil { image = Self.load(bundleID) }
        }
        .accessibilityHidden(true)
    }

    private static func load(_ bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

/// Your hours: twenty-four pixel columns, eight cells tall, the same cell language
/// as the 12-month grid. There is no tooltip: the readout above is the tooltip.
public struct HoursCard: View {
    private let hours: [Int]
    @State private var hovered: Int?

    public init(hours: [Int]) {
        self.hours = hours
    }

    private var values: [Int] { Array((hours + Array(repeating: 0, count: 24)).prefix(24)) }

    private var peak: Int? {
        guard let max = values.max(), max > 0 else { return nil }
        return values.firstIndex(of: max)
    }

    private var focus: Int? { hovered ?? peak }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Your hours", note: "Words by hour, last 90 days")
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    Metric(hovered == nil ? "Peak hour" : "Hour",
                           value: focus?.hourLabel ?? "None",
                           note: focus.map { "\(values[$0].formatted()) words" } ?? "no data yet")
                    Spacer(minLength: 0)
                    HourColumns(values: values, peak: peak, hovered: $hovered)
                    HourAxis()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.snappy(duration: 0.15), value: focus)
    }
}

public struct HourColumns: View {
    private let values: [Int]
    private let peak: Int?
    @Binding private var hovered: Int?
    @Environment(\.displayScale) private var scale
    @State private var width: CGFloat = 0

    private let rows = 8
    private let gap: CGFloat = 3

    public init(values: [Int], peak: Int?, hovered: Binding<Int?>) {
        self.values = values
        self.peak = peak
        _hovered = hovered
    }

    private func cell(for width: CGFloat) -> CGFloat {
        max(1, floor(((width - gap * 23) / 24) * scale) / scale)
    }

    public var body: some View {
        Canvas { context, size in
            let cell = cell(for: size.width)
            let pitch = cell + gap
            let stack = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
            let top = size.height - stack
            let maxValue = max(values.max() ?? 0, 1)
            for hour in 0..<min(values.count, 24) {
                let value = values[hour]
                let lit = value == 0
                    ? 0
                    : max(1, Int((Double(value) / Double(maxValue) * Double(rows)).rounded()))
                let tone = hour == hovered ? Ramp.blue[4]
                    : hour == peak ? Ramp.blue[3]
                    : Ramp.blue[2]
                for row in 0..<rows {
                    let rect = CGRect(x: CGFloat(hour) * pitch,
                                      y: top + CGFloat(rows - 1 - row) * pitch,
                                      width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                                 with: .color(row < lit ? tone : Tok.well))
                }
            }
        }
        .frame(height: 96)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { value in
            width = value
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let pitch = cell(for: width) + gap
                hovered = min(max(Int(point.x / pitch), 0), 23)
            case .ended:
                hovered = nil
            }
        }
        .accessibilityLabel("Dictation words by hour of day")
    }
}

/// Four labels at 12 AM, 6 AM, 12 PM and 6 PM, each a quarter of the width.
private struct HourAxis: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(hour.hourLabel)
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

public extension Int {
    /// 0...23 to "2 PM", or "14" in 24-hour locales.
    var hourLabel: String {
        let date = Calendar.current.date(bySettingHour: self, minute: 0, second: 0,
                                         of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
