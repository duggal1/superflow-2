import SuperflowDesignSystem
import SwiftUI

public struct ActivityDay: Equatable, Sendable, Identifiable {
    public let date: Date
    public let words: Int
    public let level: Int
    public var id: Date { date }
    public init(date: Date, words: Int, level: Int) {
        self.date = date; self.words = words; self.level = level
    }
}

public enum ActivityLevel {
    public static func assign(_ words: [Int]) -> [Int] {
        let nz = words.filter { $0 > 0 }.sorted()
        guard !nz.isEmpty else { return words.map { _ in 0 } }
        func q(_ p: Double) -> Int { nz[min(nz.count - 1, Int(Double(nz.count) * p))] }
        let t = [q(0.25), q(0.5), q(0.75)]
        return words.map { w in w == 0 ? 0 : 1 + t.filter { cut in w > cut }.count }
    }
}

public struct ActivityBlock {
    public struct Cell { public let col: Int; public let row: Int; public let day: ActivityDay }
    public let month: Date
    public let cols: Int
    public let cells: [Cell]

    public static func make(_ days: [ActivityDay]) -> [ActivityBlock] {
        let cal = Calendar.current
        var byMonth: [Date: [ActivityDay]] = [:]
        for d in days {
            let m = cal.dateInterval(of: .month, for: d.date)?.start ?? d.date
            byMonth[m, default: []].append(d)
        }
        return byMonth.keys.sorted().map { m in
            let offset = (cal.component(.weekday, from: m) - cal.firstWeekday + 7) % 7
            let raw = byMonth[m, default: []].sorted { $0.date < $1.date }.map { d -> (Int, Int, ActivityDay) in
                let i = offset + cal.component(.day, from: d.date) - 1
                return (i / 7, i % 7, d)
            }
            let minCol = raw.map(\.0).min() ?? 0
            let maxCol = raw.map(\.0).max() ?? 0
            return ActivityBlock(month: m, cols: maxCol - minCol + 1,
                                 cells: raw.map { Cell(col: $0.0 - minCol, row: $0.1, day: $0.2) })
        }
    }

    public init(month: Date, cols: Int, cells: [Cell]) {
        self.month = month; self.cols = cols; self.cells = cells
    }
}

public struct ActivityYear: View {
    public let days: [ActivityDay]
    public var animatesIn = true

    private let blocks: [ActivityBlock]
    private let today: Date?
    private let firstActive: Date?
    private let total: Int

    @State private var hovered: ActivityDay?
    @State private var width: CGFloat = 0
    @State private var reveal: CGFloat = 0
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated fileprivate static let gap: CGFloat = 3
    nonisolated fileprivate static let monthGap: CGFloat = 8
    nonisolated fileprivate static let rows = 7

    public init(days: [ActivityDay], animatesIn: Bool = true) {
        self.days = days
        self.animatesIn = animatesIn
        self.blocks = ActivityBlock.make(days)
        self.today = days.last?.date
        self.firstActive = days.first { $0.words > 0 }?.date
        self.total = days.reduce(0) { $0 + $1.words }
    }

    private struct Metrics {
        let cell: CGFloat, pitch: CGFloat, height: CGFloat
        let originX: [CGFloat]
        init(width: CGFloat, blocks: [ActivityBlock], scale: CGFloat) {
            let cols = max(blocks.reduce(0) { $0 + $1.cols }, 1)
            let inner = blocks.reduce(0) { $0 + $1.cols - 1 }
            let free = width - CGFloat(inner) * ActivityYear.gap - CGFloat(max(blocks.count - 1, 0)) * ActivityYear.monthGap
            cell = max(floor((free / CGFloat(cols)) * scale) / scale, 1)
            pitch = cell + ActivityYear.gap
            height = CGFloat(ActivityYear.rows) * cell + CGFloat(ActivityYear.rows - 1) * ActivityYear.gap
            var x: CGFloat = 0
            var xs: [CGFloat] = []
            for b in blocks {
                xs.append(x)
                x += CGFloat(b.cols) * cell + CGFloat(b.cols - 1) * ActivityYear.gap + ActivityYear.monthGap
            }
            originX = xs
        }
    }

    public var body: some View {
        let m = Metrics(width: width, blocks: blocks, scale: scale)
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(alignment: .leading, spacing: 8) {
                Canvas { ctx, _ in draw(&ctx, m) }
                    .frame(height: m.height)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): hovered = day(at: p, m)
                        case .ended: hovered = nil
                        }
                    }
                monthLabels(m)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .opacity(width > 0 ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation words per day for the last 12 months")
        .accessibilityValue("\(total.formatted()) words")
        .task { await runReveal() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last 12 months").font(AppType.title.font).foregroundStyle(Tok.text)
                readout.frame(height: 16, alignment: .leading)
            }
            Spacer(minLength: 16)
            Legend()
        }
    }

    @ViewBuilder private var readout: some View {
        if let h = hovered {
            HStack(spacing: 8) {
                Text(h.date, format: .dateTime.month(.abbreviated).day()).foregroundStyle(Tok.text2)
                Text(h.words.formatted())
                    .font(Typography.secondaryMedium).monospacedDigit().foregroundStyle(Tok.text)
                    .contentTransition(.numericText(value: Double(h.words)))
                Text(h.words == 1 ? "word" : "words").foregroundStyle(Tok.text2)
            }
            .font(AppType.caption.font)
            .transition(.opacity)
        } else {
            Text("Dictation words per day").font(AppType.caption.font).foregroundStyle(Tok.text2).transition(.opacity)
        }
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

    private func draw(_ ctx: inout GraphicsContext, _ m: Metrics) {
        for (bi, b) in blocks.enumerated() {
            for c in b.cells {
                let x = m.originX[bi] + CGFloat(c.col) * m.pitch
                let y = CGFloat(c.row) * m.pitch
                let order = 1 - (x + m.cell / 2) / max(width, 1)
                guard order <= reveal else { continue }

                let rect = CGRect(x: x, y: y, width: m.cell, height: m.cell)
                let d = c.day
                let isDust = firstActive.map { d.date < $0 } ?? true

                if d.date == today {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous), with: .color(Tok.text))
                } else if d.id == hovered?.id {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous), with: .color(Ramp.blue[4]))
                } else if isDust {
                    let dot = CGRect(x: snap(rect.midX - 1), y: snap(rect.midY - 1), width: 2, height: 2)
                    ctx.fill(Path(dot), with: .color(Tok.control))
                } else {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                             with: .color(Ramp.blue[min(max(d.level, 0), 4)]))
                }
            }
        }
    }

    private func day(at p: CGPoint, _ m: Metrics) -> ActivityDay? {
        let g = ActivityYear.gap
        for (bi, b) in blocks.enumerated() {
            for c in b.cells {
                let r = CGRect(x: m.originX[bi] + CGFloat(c.col) * m.pitch - g / 2,
                               y: CGFloat(c.row) * m.pitch - g / 2, width: m.pitch, height: m.pitch)
                if r.contains(p) { return c.day }
            }
        }
        return nil
    }

    private func monthLabels(_ m: Metrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                if b.cols >= 3 {
                    Text(b.month, format: .dateTime.month(.abbreviated))
                        .font(AppType.caption.font).foregroundStyle(Tok.text2)
                        .fixedSize()
                        .offset(x: m.originX[i])
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .topLeading)
    }

    private func runReveal() async {
        guard animatesIn, !reduceMotion else { reveal = 1; return }
        for k in 1...14 {
            try? await Task.sleep(for: .milliseconds(600 / 14))
            reveal = CGFloat(k) / 14
        }
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Less").font(AppType.caption.font).foregroundStyle(Tok.text2)
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Ramp.blue[i]).frame(width: 8, height: 8)
                }
            }
            Text("More").font(AppType.caption.font).foregroundStyle(Tok.text2)
        }
        .accessibilityHidden(true)
    }
}
