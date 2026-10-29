import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public enum DownloadState: Equatable, Sendable {
    case idle
    case downloading(Double?)
    case verifying
    case installed
    case failed(String)
}

public struct DownloadCard<Leading: View, Trailing: View>: View {
    private let title: String
    private let detail: String
    private let state: DownloadState
    private let totalBytes: Int64?
    private let leading: Leading
    private let trailing: Trailing

    @State private var meter = ThroughputMeter()
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String,
                detail: String,
                state: DownloadState,
                totalBytes: Int64?,
                @ViewBuilder leading: () -> Leading,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.state = state
        self.totalBytes = totalBytes
        self.leading = leading()
        self.trailing = trailing()
    }

    private var progress: Double? { if case .downloading(let p) = state { p } else { nil } }
    private var showReadout: Bool { if case .downloading(let p) = state, p != nil, totalBytes != nil { true } else { false } }
    private var total: Double { Double(totalBytes ?? 0) }
    private var done: Double { total * (progress ?? 0) }
    private var metricFont: Font { AppType.metric.font }
    private var rollAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }

    private var fillAmount: Double {
        switch state {
        case .downloading(let p): p ?? 0
        case .verifying, .installed: 1
        case .idle, .failed: 0
        }
    }
    private var fillVisible: Bool {
        switch state { case .downloading, .verifying: true; default: false }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if showReadout { readout.transition(.opacity) }
        }
        .frame(maxWidth: .infinity)
        .background {
            FrontShape(progress: fillAmount, scale: scale)
                .fill(Tok.accentFill)
                .opacity(fillVisible ? 1 : 0)
                .animation(reduceMotion ? nil : Motion.settle, value: fillAmount)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: fillVisible)
        }
        .background(Tok.surface)
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .contrastStroke(radius: Radius.card)
        .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: showReadout)
        .accessibilityElement(children: .contain)
        .task(id: showReadout) {
            guard showReadout else { return }
            meter.reset()
            if let progress { meter.record(bytes: progress * total) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                meter.tick()
            }
        }
        .onChange(of: progress) { _, p in
            guard showReadout, let p else { return }
            meter.record(bytes: p * total)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            leading.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppType.label.font)
                    .foregroundStyle(Tok.text)
                    .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "")
                detailLine
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
    }

    @ViewBuilder private var detailLine: some View {
        switch state {
        case .downloading(let p) where p != nil && totalBytes != nil:
            Text(DownloadFormat.bytesLine(done: done, total: total))
                .font(AppType.caption.font).monospacedDigit().foregroundStyle(Tok.text2)
                .contentTransition(.numericText(value: done))
                .animation(rollAnimation, value: done)
        case .verifying:
            Text("Verifying").font(AppType.caption.font).foregroundStyle(Tok.text2)
        case .failed(let message):
            Text(message).font(AppType.caption.font).foregroundStyle(Tok.text2).lineLimit(1)
        default:
            Text(detail).font(AppType.caption.font).foregroundStyle(Tok.text2).lineLimit(1)
        }
    }

    private var readout: some View {
        let speed = meter.speed
        let rate = DownloadFormat.rate(speed)
        let left = DownloadFormat.remaining(bytesLeft: max(total - done, 0), speed: speed)

        return HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("88.8").font(metricFont).monospacedDigit().hidden()
                        .overlay(alignment: .leading) {
                            Text(rate.value)
                                .font(metricFont).monospacedDigit().foregroundStyle(Tok.text)
                                .contentTransition(.numericText(value: speed))
                                .animation(rollAnimation, value: rate.value)
                        }
                    Text(rate.unit).font(AppType.body.font).foregroundStyle(Tok.text2)
                }
                Text(left)
                    .font(AppType.caption.font).monospacedDigit().foregroundStyle(Tok.text2)
                    .contentTransition(.numericText())
                    .animation(rollAnimation, value: left)
            }
            .frame(width: 120, alignment: .leading)

            ThroughputStrip(meter: meter)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .accessibilityHidden(true)
    }
}

private struct FrontShape: Shape {
    var progress: Double
    var scale: CGFloat
    var animatableData: Double { get { progress } set { progress = newValue } }

    func path(in rect: CGRect) -> Path {
        let cell: CGFloat = 4
        let edge = (rect.width * CGFloat(progress) * scale).rounded() / scale
        let gridEdge = floor(edge / cell) * cell
        let solid = max(gridEdge - cell * 4, 0)
        var p = Path()
        if solid > 0 { p.addRect(CGRect(x: 0, y: 0, width: solid, height: rect.height)) }

        let cols = Int(((gridEdge - solid) / cell).rounded())
        let rows = Int((rect.height / cell).rounded(.up))
        let density: [Double] = [0.14, 0.32, 0.55, 0.80]
        for k in 0..<cols {
            let x = gridEdge - CGFloat(k + 1) * cell
            let ci = Int(x / cell)
            for r in 0..<rows where Double(cellHash(ci, r, 7)) < density[k] {
                p.addRect(CGRect(x: x, y: CGFloat(r) * cell, width: cell, height: cell))
            }
        }
        return p
    }
}

// MARK: - Pixel strip

struct ThroughputStrip: View {
    let meter: ThroughputMeter
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows = 6
    private let gap: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            let values = meter.history
            let lastPush = meter.lastPush
            Canvas { ctx, size in
                draw(&ctx, size, values: values, lastPush: lastPush, now: tl.date)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize,
                      values: [Double], lastPush: Date, now: Date) {
        let n = ThroughputMeter.columns
        guard size.width > 0, values.count == n + 1 else { return }

        let cell = floor(((size.width - gap * CGFloat(n - 1)) / CGFloat(n)) * scale) / scale
        guard cell > 0 else { return }
        let pitch = cell + gap
        let stack = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
        let top = size.height - stack

        let phase: CGFloat = reduceMotion
            ? 1
            : CGFloat(min(max(now.timeIntervalSince(lastPush) / ThroughputMeter.interval, 0), 1))
        let maxV = max(values.max() ?? 0, ThroughputMeter.floorSpeed)

        for (k, v) in values.enumerated() {
            let x = snap((CGFloat(k) - phase) * pitch)
            if x + cell < 0 || x > size.width { continue }

            let lit = v <= 0 ? 0 : max(1, Int((v / maxV * Double(rows)).rounded()))
            let rel = Double(k) / Double(n)
            let tone: Color = k == n ? Ramp.blue[4]
                            : rel > 0.66 ? Ramp.blue[3]
                            : rel > 0.33 ? Ramp.blue[2]
                            :              Ramp.blue[1]

            for r in 0..<rows {
                let rect = CGRect(x: x, y: top + CGFloat(rows - 1 - r) * pitch, width: cell, height: cell)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                         with: .color(r < lit ? tone : Tok.well))
            }
        }
    }
}

@MainActor @Observable
final class ThroughputMeter {
    static let columns = 36
    static let interval: TimeInterval = 0.5
    static let floorSpeed: Double = 2_000_000

    private(set) var speed: Double = 0
    private(set) var history = [Double](repeating: 0, count: ThroughputMeter.columns + 1)
    private(set) var lastPush = Date()

    @ObservationIgnored private var window: [(t: Date, bytes: Double)] = []

    func reset(now: Date = .now) {
        speed = 0
        history = [Double](repeating: 0, count: Self.columns + 1)
        lastPush = now
        window.removeAll()
    }

    func record(bytes: Double, at now: Date = .now) {
        window.append((now, bytes))
        trim(now)
    }

    func tick(now: Date = .now) {
        trim(now)
        var raw = 0.0
        if let first = window.first, let last = window.last {
            let dt = now.timeIntervalSince(first.t)
            if dt >= 0.5 { raw = max(0, (last.bytes - first.bytes) / dt) }
        }
        speed += (raw - speed) * 0.35
        if speed < 1_000 { speed = 0 }

        if now.timeIntervalSince(lastPush) >= Self.interval - 0.01 {
            history.removeFirst()
            history.append(speed)
            lastPush = now
        }
    }

    private func trim(_ now: Date) {
        window.removeAll { now.timeIntervalSince($0.t) > 3 }
    }
}

enum DownloadFormat {
    static func rate(_ bps: Double) -> (value: String, unit: String) {
        let mb = bps / 1_000_000
        if mb >= 100 { return (String(format: "%.0f", mb), "MB/s") }
        if mb >= 0.95 { return (String(format: "%.1f", mb), "MB/s") }
        if bps >= 1_000 { return (String(format: "%.0f", bps / 1_000), "KB/s") }
        return ("0.0", "MB/s")
    }

    static func bytesLine(done: Double, total: Double) -> String {
        let totalFraction = total >= 100_000_000 ? 0 : 1
        return String(format: "%.1f of %.\(totalFraction)f MB", done / 1_000_000, total / 1_000_000)
    }

    static func remaining(bytesLeft: Double, speed: Double) -> String {
        guard speed > 50_000 else { return "Estimating" }
        let s = Int((bytesLeft / speed).rounded(.up))
        if s < 60 { return "\(s) s left" }
        if s < 3600 { return "\((s + 59) / 60) min left" }
        return "\(s / 3600) h \((s % 3600) / 60) min left"
    }
}
