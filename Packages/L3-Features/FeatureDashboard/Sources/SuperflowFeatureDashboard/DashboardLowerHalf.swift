import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

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

/// Your hours: the day cut into three eight-hour blocks, so the shape of the
/// working day is legible before reading a single label. The readout above is
/// the tooltip; there is no floating label.
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
                VStack(alignment: .leading, spacing: Space.lg) {
                    readout
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HourColumns(values: values, peak: peak, hovered: $hovered)
                        HourBlocks()
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.snappy(duration: 0.15), value: focus)
    }

    /// Label and number on the left, the count for that hour on the right edge.
    /// The pair is the whole story; no caption underneath repeating the unit.
    private var readout: some View {
        HStack(alignment: .lastTextBaseline, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(hovered == nil ? "Peak hour" : "Hour")
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
                Text(focus?.hourLabel ?? "None")
                    .appType(.metric)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text)
                    .contentTransition(.numericText(value: Double(focus ?? -1)))
            }
            Spacer(minLength: Space.sm)
            Text(focus.map { "\(values[$0].formatted()) words" } ?? "No words yet")
                .appType(.caption)
                .monospacedDigit()
                .foregroundStyle(Tok.text2)
                .contentTransition(.numericText(value: Double(focus.map { values[$0] } ?? 0)))
        }
    }
}

/// Twenty-four columns, eight cells tall, split into three blocks of eight hours.
/// The gap between blocks is the same month gap the 12-month graph uses, so the
/// two charts are one language.
public struct HourColumns: View {
    private let values: [Int]
    private let peak: Int?
    @Binding private var hovered: Int?
    @Environment(\.displayScale) private var scale
    @State private var width: CGFloat = 0

    private let rows = 8
    private let gap: CGFloat = 3
    private static let blocks = 3
    private static let blockGap: CGFloat = 12
    private static let blockHours = 8

    public init(values: [Int], peak: Int?, hovered: Binding<Int?>) {
        self.values = values
        self.peak = peak
        _hovered = hovered
    }

    private var blockWidth: CGFloat { max((width - 2 * Self.blockGap) / 3, 1) }

    private var cell: CGFloat {
        max(1, floor(((blockWidth - gap * 7) / 8) * scale) / scale)
    }

    private var pitch: CGFloat { cell + gap }

    private func origin(of hour: Int) -> CGFloat {
        CGFloat(hour / Self.blockHours) * (blockWidth + Self.blockGap)
    }

    private func hour(at x: CGFloat) -> Int? {
        guard width > 0 else { return nil }
        for block in stride(from: Self.blocks - 1, through: 0, by: -1) {
            let start = CGFloat(block) * (blockWidth + Self.blockGap)
            if x >= start || block == 0 {
                let column = min(max(Int((x - start) / pitch), 0), Self.blockHours - 1)
                return block * Self.blockHours + column
            }
        }
        return nil
    }

    public var body: some View {
        Canvas { context, _ in
            let maxValue = max(values.max() ?? 0, 1)
            for hour in 0..<min(values.count, 24) {
                let value = values[hour]
                let lit = value == 0
                    ? 0
                    : max(1, Int((Double(value) / Double(maxValue) * Double(rows)).rounded()))
                let tone = hour == hovered ? Ramp.blue[4]
                    : hour == peak ? Ramp.blue[3]
                    : Ramp.blue[2]
                let x = Pixel.snap(origin(of: hour) + CGFloat(hour % Self.blockHours) * pitch, scale)
                for row in 0..<rows {
                    let rect = CGRect(x: x,
                                      y: CGFloat(rows - 1 - row) * pitch,
                                      width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                                 with: .color(row < lit ? tone : Tok.well))
                }
            }
        }
        .frame(height: CGFloat(rows) * (width > 0 ? cell : 8) + CGFloat(rows - 1) * gap)
        .opacity(width > 0 ? 1 : 0)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { value in
            width = value
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hovered = hour(at: point.x)
            case .ended:
                hovered = nil
            }
        }
        .accessibilityLabel("Dictation words by hour of day")
    }
}

/// One label at the start of each eight-hour block: 12 AM, 8 AM, 4 PM.
private struct HourBlocks: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: 24, by: 8)), id: \.self) { hour in
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
