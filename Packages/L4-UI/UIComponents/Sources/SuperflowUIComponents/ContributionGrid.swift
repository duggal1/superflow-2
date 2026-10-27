import SuperflowDesignSystem
import SuperflowKernel
import SwiftUI

public struct ContributionGridDay: Sendable, Equatable, Identifiable {
    public let day: String
    public let words: Int
    public let level: Int
    public let isFuture: Bool

    public var id: String { day }

    public init(day: String, words: Int, level: Int, isFuture: Bool) {
        self.day = day
        self.words = words
        self.level = level
        self.isFuture = isFuture
    }
}

public enum ContributionLayout {
    public static let levelCount = 5

    /// GitHub columns are Sunday-first weeks. The engine already returns
    /// Sunday-first cells, so chunking is all the layout needs.
    public static func columns(_ days: [ContributionGridDay]) -> [[ContributionGridDay]] {
        guard !days.isEmpty else { return [] }
        return stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(days.count, start + 7)])
        }
    }

    public static func monthLabels(_ days: [ContributionGridDay]) -> [String] {
        var labels: [String] = []
        var lastMonth = ""
        for day in days {
            let month = String(day.day.prefix(7))
            guard month != lastMonth else { continue }
            lastMonth = month
            if let date = LocalDay.date(from: day.day) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                labels.append(formatter.string(from: date))
            }
        }
        return labels
    }
}

/// 53 columns by 7 rows, drawn straight on the canvas. No card, no border.
public struct ContributionGrid: View {
    public static let ramp: [Color] = [
        Color(light: Color(hex: 0xE9E9E9), dark: Color(hex: 0x171717)),
        Color(light: Color(hex: 0xDBEAFE), dark: Color(hex: 0x172554)),
        Color(light: Color(hex: 0x93C5FD), dark: Color(hex: 0x1E3A8A)),
        Color(hex: 0x2563EB),
        Color(light: Color(hex: 0x1E3A8A), dark: Color(hex: 0x60A5FA)),
    ]

    private let days: [ContributionGridDay]
    private let gap: CGFloat
    private let animateReveal: Bool
    @State private var hovered: ContributionGridDay?
    @State private var hoverPoint: CGPoint = .zero
    @State private var reveal: CGFloat = 0
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ days: [ContributionGridDay], gap: CGFloat = 3,
                animateReveal: Bool = true) {
        self.days = days
        self.gap = gap
        self.animateReveal = animateReveal
    }

    private var columns: [[ContributionGridDay]] { ContributionLayout.columns(days) }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            grid
            legend
        }
        .accessibilityElement(children: .contain)
        .task { await revealOnce() }
    }

    private var grid: some View {
        let columns = columns
        return Canvas { context, size in
            let count = max(columns.count, 1)
            let cell = max(1, floor(((size.width - gap * CGFloat(count - 1)) / CGFloat(count)) * scale) / scale)
            let pitch = cell + gap
            let cutoff = revealCutoff
            for (x, column) in columns.enumerated() {
                for (y, day) in column.enumerated() {
                    guard revealOrder(column: x, row: y, columns: count,
                                      rows: 7) <= cutoff else { continue }
                    let rect = CGRect(x: CGFloat(x) * pitch, y: CGFloat(y) * pitch,
                                      width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                                 with: .color(color(level: day.isFuture ? 0 : day.level)))
                }
            }
        }
        .frame(height: gridHeight)
        .frame(maxWidth: .infinity)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hoverPoint = point
                hovered = day(at: point)
            case .ended:
                hovered = nil
            }
        }
        .overlay(alignment: .topLeading) { tooltip }
        .accessibilityLabel("Dictation words per day for the last 12 months")
    }

    /// Whole steps, radial from the centre, jittered per cell (§8.8), then static.
    private var revealCutoff: CGFloat {
        guard animateReveal, !reduceMotion else { return 1 }
        let eased = 1 - pow(1 - reveal, 3)
        return (eased * 14).rounded(.up) / 14
    }

    private func revealOrder(column: Int, row: Int, columns: Int, rows: Int) -> CGFloat {
        let gx = (CGFloat(column) + 0.5 - CGFloat(columns) / 2) / (CGFloat(columns) / 2)
        let gy = (CGFloat(row) + 0.5 - CGFloat(rows) / 2) / (CGFloat(rows) / 2)
        let radial = min(1, hypot(gx, gy) / CGFloat(2).squareRoot())
        return radial * 0.82 + cellNoise(column, row) * 0.18
    }

    private func cellNoise(_ x: Int, _ y: Int) -> CGFloat {
        var value = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263) &+ 11
        value = (value ^ (value >> 13)) &* 1_274_126_177
        value ^= value >> 16
        return CGFloat(value & 0xFFFF) / CGFloat(0xFFFF)
    }

    private func revealOnce() async {
        guard animateReveal, !reduceMotion else {
            reveal = 1
            return
        }
        guard reveal == 0 else { return }
        let steps = 14
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(600 / steps))
            reveal = CGFloat(step) / CGFloat(steps)
        }
    }

    private var gridHeight: CGFloat {
        // 7 rows at the same pitch the canvas computes, so 53 columns fit the width.
        let count = max(columns.count, 1)
        let available = Space.pageMaxWidth - Space.pagePadding * 2
        let cell = ((available - gap * CGFloat(count - 1)) / CGFloat(count)).rounded()
        return cell * 7 + gap * 6
    }

    private func color(level: Int) -> Color {
        Self.ramp[min(max(level, 0), Self.ramp.count - 1)]
    }

    private var legend: some View {
        HStack(spacing: Space.xxs) {
            Text("Less")
                .font(Typography.secondary)
                .foregroundStyle(Tok.text2)
            ForEach(0..<ContributionLayout.levelCount, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(level: level))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .font(Typography.secondary)
                .foregroundStyle(Tok.text2)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tooltip: some View {
        if let hovered {
            GlassSurface(radius: Radius.field) {
                Text("\(hovered.words.formatted()) words, \(shortDay(hovered.day))")
                    .font(Typography.secondary)
                    .foregroundStyle(Tok.text)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xxs)
            }
            .offset(x: max(0, hoverPoint.x - 60), y: max(0, hoverPoint.y - 28))
            .allowsHitTesting(false)
        }
    }

    private func day(at point: CGPoint) -> ContributionGridDay? {
        let columns = columns
        guard !columns.isEmpty else { return nil }
        let available = Space.pageMaxWidth - Space.pagePadding * 2
        let count = CGFloat(columns.count)
        let cell = ((available - gap * (count - 1)) / count).rounded()
        let pitch = cell + gap
        let column = Int(point.x / pitch)
        let row = Int(point.y / pitch)
        guard column >= 0, column < columns.count, row >= 0, row < columns[column].count else {
            return nil
        }
        return columns[column][row]
    }

    private func shortDay(_ day: String) -> String {
        guard let date = LocalDay.date(from: day) else { return day }
        let parser = DateFormatter()
        parser.dateFormat = "MMM d"
        return parser.string(from: date)
    }
}
