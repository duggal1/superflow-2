import AppKit
import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

@MainActor @Observable
final class BloomModel {
    enum Phase { case idle, holding(Date), collapsing(from: CGFloat, at: Date) }
    private(set) var phase: Phase = .idle
    private(set) var releases = 0
    @ObservationIgnored private var settle: Task<Void, Never>?

    var isActive: Bool { if case .idle = phase { false } else { true } }

    func press(now: Date = .now) { settle?.cancel(); phase = .holding(now) }

    func release(now: Date = .now) {
        guard case .holding(let t0) = phase else { return }
        phase = .collapsing(from: PixelBloom.radius(held: now.timeIntervalSince(t0)), at: now)
        releases += 1
        settle = Task {
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            phase = .idle
        }
    }
}

struct PixelBloom: View {
    let model: BloomModel
    let source: CGRect?
    let clear: [CGRect]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cell: CGFloat = 8
    static let maxCells: CGFloat = 20
    static let steps: CGFloat = 14

    static func radius(held: TimeInterval) -> CGFloat {
        let x = min(max(held / 0.8, 0), 1)
        let eased = 1 - pow(1 - x, 3)
        return max(2, maxCells * (CGFloat(eased) * steps).rounded(.up) / steps)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.isActive || reduceMotion)) { tl in
            Canvas { ctx, size in
                guard let source else { return }
                let r = currentRadius(now: tl.date)
                guard r > 0 else { return }
                draw(&ctx, size, center: CGPoint(x: source.midX, y: source.midY), r: r)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func currentRadius(now: Date) -> CGFloat {
        switch model.phase {
        case .idle: return 0
        case .holding(let t0): return reduceMotion ? Self.maxCells : Self.radius(held: now.timeIntervalSince(t0))
        case .collapsing(let from, let t0):
            if reduceMotion { return 0 }
            let p = min(max(now.timeIntervalSince(t0) / 0.45, 0), 1)
            let remaining = 1 - pow(p, 2)
            return from * (CGFloat(remaining) * Self.steps).rounded(.down) / Self.steps
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, center c: CGPoint, r: CGFloat) {
        let cell = Self.cell
        let dark = scheme == .dark
        let i0 = max(Int(floor((c.x - (r + 2) * cell) / cell)), 0)
        let i1 = min(Int(ceil((c.x + (r + 2) * cell) / cell)), Int(size.width / cell))
        let j0 = max(Int(floor((c.y - (r + 2) * cell) / cell)), 0)
        let j1 = min(Int(ceil((c.y + (r + 2) * cell) / cell)), Int(size.height / cell))
        guard i0 < i1, j0 < j1 else { return }
        let holes = clear.map { $0.insetBy(dx: -cell, dy: -cell) }

        for j in j0..<j1 {
            for i in i0..<i1 {
                let p = CGPoint(x: (CGFloat(i) + 0.5) * cell, y: (CGFloat(j) + 0.5) * cell)
                let dist = hypot(p.x - c.x, p.y - c.y) / cell
                let jitter = (cellHash(i, j, 21) - 0.5) * 2.2
                guard dist + jitter <= r else { continue }
                if holes.contains(where: { $0.contains(p) }) { continue }
                let t = dist / max(r, 1)
                let v = 0.80 - 0.40 * t + (cellHash(i, j, 26) - 0.5) * 0.10
                guard let color = Tone.color(v, i, j, dark: dark) else { continue }
                ctx.fill(Path(CGRect(x: CGFloat(i) * cell, y: CGFloat(j) * cell, width: cell, height: cell)),
                         with: .color(color), style: FillStyle(antialiased: false))
            }
        }
    }
}

struct HeroKeyCap: View {
    let label: String
    var down = false
    var body: some View {
        Text(label)
            .appType(.label).foregroundStyle(Tok.text)
            .frame(width: 48, height: 32)
            .background(down ? Tok.controlPressed : Tok.controlHover, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .offset(y: down ? 4 : 0)
            .animation(.snappy(duration: 0.12), value: down)
            .background { RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(Tok.control).offset(y: 4) }
            .padding(.bottom, 4)
    }
}

struct FnDemo: View {
    @Environment(BloomModel.self) private var bloom
    @State private var down = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                HeroKeyCap(label: "fn", down: down)
                    .bloomSource()
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in press() }.onEnded { _ in release() })
                    .clickable()
                    .focusStep(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .accessibilityLabel("fn key")
                    .accessibilityHint("Press and hold to see what Superflow does")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        Task { press(); try? await Task.sleep(for: .milliseconds(700)); release() }
                    }
                Text("Hold, speak, release.").appType(.reading).foregroundStyle(Tok.text).clearsPixels()
            }
            TypedLine(text: "The budget is $12,000, and we meet on Tuesday at 3 PM.", trigger: bloom.releases)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .clearsPixels()
        }
        .onFnChange { isDown in isDown ? press() : release() }
    }

    private func press() {
        guard !down else { return }
        down = true
        bloom.press()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    private func release() {
        guard down else { return }
        down = false
        bloom.release()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }
}

struct TypedLine: View {
    let text: String
    let trigger: Int
    @State private var count = 0
    @State private var caret = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            Text(String(text.prefix(count))).appType(.reading).foregroundStyle(Tok.text)
            if caret { Rectangle().fill(Tok.text).frame(width: 2, height: 16) }
        }
        .task(id: trigger) {
            guard trigger > 0 else { return }
            count = 0
            if reduceMotion { count = text.count; return }
            caret = true
            try? await Task.sleep(for: .milliseconds(240))
            for n in 1...text.count {
                guard !Task.isCancelled else { return }
                count = n
                try? await Task.sleep(for: .milliseconds(24))
            }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { caret = false }
        }
        .accessibilityLabel(count > 0 ? text : "")
    }
}

@MainActor final class FnWatcher {
    private var token: Any?
    private var isDown = false
    func start(_ handler: @escaping @MainActor (Bool) -> Void) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let down = event.modifierFlags.contains(.function)
            MainActor.assumeIsolated {
                if let self, down != self.isDown { self.isDown = down; handler(down) }
            }
            return event
        }
    }
    func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil; isDown = false }
}

private struct FnMonitor: ViewModifier {
    let perform: @MainActor (Bool) -> Void
    @State private var watcher = FnWatcher()
    func body(content: Content) -> some View {
        content.onAppear { watcher.start(perform) }.onDisappear { watcher.stop() }
    }
}
extension View { func onFnChange(_ perform: @escaping @MainActor (Bool) -> Void) -> some View { modifier(FnMonitor(perform: perform)) } }
