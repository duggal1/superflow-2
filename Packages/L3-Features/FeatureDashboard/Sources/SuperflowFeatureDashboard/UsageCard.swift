import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

public struct UsageCard: View {
    public let usage: [AppUsage]
    @Binding public var range: UsageRange
    public var isExample: Bool
    public var animatesIn: Bool
    @State private var hovered: String?
    @State private var reveal: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(usage: [AppUsage], range: Binding<UsageRange>, isExample: Bool = false, animatesIn: Bool = true) {
        self.usage = usage
        _range = range
        self.isExample = isExample
        self.animatesIn = animatesIn
    }

    private var rows: [AppUsage] { Array(usage.prefix(6)) }
    private var total: Int { max(1, usage.reduce(0) { $0 + $1.words }) }
    private var top: Double { Double(max(1, rows.first?.words ?? 1)) }
    private var readout: String {
        guard let hovered, let app = usage.first(where: { $0.id == hovered }) else { return "Words typed in each app" }
        return "\(AppNameLookup.name(for: app.bundleID)): \(Humanize.words(app.words)), \(app.sessions) sessions, \(Humanize.duration(app.seconds))"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: Space.md) {
                SectionHeader("Where you dictate", note: readout)
                Spacer(minLength: Space.md)
                if isExample { Badge("Example") }
                else {
                    Segmented(selection: $range, items: [
                        .init("7 days", value: .week),
                        .init("30 days", value: .month),
                        .init("All time", value: .all),
                    ])
                }
            }
            Card(padding: Space.xs) {
                VStack(spacing: Space.xxs) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { rank, app in
                        usageRow(app, rank: rank)
                    }
                }
            }
        }
        .task { await develop() }
    }

    private func usageRow(_ app: AppUsage, rank: Int) -> some View {
        UsageRowView(app: app, rank: rank,
                     share: Double(app.words) / Double(total),
                     fraction: Double(app.words) / top, reveal: reveal,
                     hovered: $hovered)
    }

    private func develop() async {
        guard animatesIn, reveal == 0, !reduceMotion else { reveal = 1; return }
        for step in 1...14 {
            do { try await Task.sleep(for: .milliseconds(43)) } catch { return }
            reveal = CGFloat(1 - pow(1 - Double(step) / 14, 3))
        }
    }
}

/// One row: icon, name, pixel barcode, words, share. Hover is local, so the
/// fill and the note under the title change together without reflowing.
private struct UsageRowView: View {
    let app: AppUsage
    let rank: Int
    let share: Double
    let fraction: Double
    let reveal: CGFloat
    @Binding var hovered: String?
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let name = AppNameLookup.name(for: app.bundleID)
        HStack(spacing: Space.sm) {
            AppIcon(bundleID: app.bundleID, size: 20)
            Text(name).appType(.label).foregroundStyle(Tok.text)
                .lineLimit(1).frame(width: 112, alignment: .leading)
            UsageBar(fraction: fraction, leader: rank == 0, reveal: reveal)
                .frame(maxWidth: .infinity).frame(height: 16)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: fraction)
            Text(app.words.formatted()).appType(.body).monospacedDigit()
                .foregroundStyle(Tok.text).frame(width: 56, alignment: .trailing)
            Text(share < 0.01 ? "<1%" : "\(Int((share * 100).rounded()))%")
                .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, Space.sm).frame(height: 40)
        .background(hover ? Tok.control : .clear,
                    in: .rect(cornerRadius: Radius.nested, style: .continuous))
        .onHover { inside in
            hover = inside
            hovered = inside ? app.id : (hovered == app.id ? nil : hovered)
        }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(app.words) words, \(app.sessions) sessions, \(Humanize.duration(app.seconds)), \(Int((share * 100).rounded())) percent")
    }
}

struct UsageBar: View, Animatable {
    nonisolated var fraction: Double
    let leader: Bool
    let reveal: CGFloat
    @Environment(\.displayScale) private var scale
    nonisolated var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 4
            let columns = max(8, Int((size.width + 1) / pitch))
            let lit = fraction <= 0 ? 0 : min(columns, max(1, Int((min(1, fraction) * Double(columns)).rounded(.up))))
            let shown = Int((Double(lit) * Double(reveal)).rounded(.down))
            let y = Pixel.snap((size.height - 10) / 2, scale)
            let head = leader ? Tok.text : Ramp.blue[4]
            for column in 0..<columns {
                let x = CGFloat(column) * pitch
                if column < shown {
                    let proportion = Double(column) / Double(max(columns - 1, 1))
                    var tone = proportion < 0.35 ? Ramp.blue[2] : proportion < 0.7 ? Ramp.blue[3] : Ramp.blue[4]
                    if column == shown - 1 || (column == shown - 2 && column.isMultiple(of: 2)) { tone = head }
                    context.fill(Path(CGRect(x: x, y: y, width: 3, height: 10)),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                } else {
                    context.fill(Path(CGRect(x: x + 1, y: y + 4, width: 1, height: 1)),
                                 with: .color(Tok.controlPressed), style: FillStyle(antialiased: false))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
