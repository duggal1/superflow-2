import AppKit
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

/// The hold that drives the pixel stage. It is a state machine, not a looping
/// animation: pressing starts one fill, releasing drains it, and nothing runs
/// while the key is up.
@MainActor @Observable
final class StageModel {
    private(set) var progress: CGFloat = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    func press(instantly: Bool) {
        task?.cancel()
        if instantly {
            progress = 1
            return
        }
        let started = Date()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let x = min(1, Date().timeIntervalSince(started) / 0.9)
                self.progress = 1 - pow(1 - x, 3)
                if x >= 1 { return }
            }
        }
    }

    func release(instantly: Bool) {
        task?.cancel()
        guard !instantly else {
            progress = 0
            return
        }
        let from = progress
        task = Task { @MainActor [weak self] in
            for step in 1...6 {
                try? await Task.sleep(for: .milliseconds(30))
                guard let self, !Task.isCancelled else { return }
                self.progress = from * (1 - CGFloat(step) / 6)
            }
        }
    }

    func reset() {
        task?.cancel()
        progress = 0
    }
}

/// A print head of blue pixels: columns land left to right while the key is held,
/// and the stage itself grows by whole rows so the padding around the key is only
/// there while the gesture is happening. Everything is a 4 pt cell on the device
/// grid, drawn unantialiased. No loop, no idle motion.
struct PixelStage: View {
    let progress: CGFloat

    static let cell: CGFloat = 4
    static let gap: CGFloat = 4
    static let maxRows = 8

    static func rows(_ progress: CGFloat) -> Int {
        Int((min(max(progress, 0), 1) * CGFloat(maxRows)).rounded())
    }

    static func height(_ progress: CGFloat) -> CGFloat {
        let rows = rows(progress)
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * cell + CGFloat(rows - 1) * gap
    }

    var body: some View {
        Canvas { ctx, size in
            let rows = Self.rows(progress)
            guard rows > 0 else { return }
            let pitch = Self.cell + Self.gap
            let columns = max(1, Int((size.width + Self.gap) / pitch))
            let front = progress * CGFloat(columns)

            for column in 0..<columns {
                guard CGFloat(column) <= front else { break }
                let height = amplitude(column)
                let lit = min(rows, max(1, Int((height * CGFloat(rows)).rounded())))
                let leading = CGFloat(column) > front - 1
                for row in 0..<lit {
                    let color = leading ? Tok.text : tone()
                    let rect = CGRect(x: CGFloat(column) * pitch,
                                      y: CGFloat(rows - 1 - row) * pitch,
                                      width: Self.cell, height: Self.cell)
                    ctx.fill(Path(rect), with: .color(color),
                             style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(height: Self.height(progress))
        .accessibilityHidden(true)
    }

    /// One blue, blue 600, for every cell. Depth comes from the row count, not a
    /// second hue or an alpha ramp.
    private func tone() -> Color {
        Tok.accent
    }

    /// Deterministic per-column height, 0.35...1. Same picture on every press.
    private func amplitude(_ column: Int) -> CGFloat {
        var hash = UInt32(truncatingIfNeeded: column) &* 374_761_393 &+ 17 &* 668_265_263
        hash = (hash ^ (hash >> 13)) &* 1_274_126_177
        hash ^= hash >> 16
        return 0.35 + 0.65 * CGFloat(hash) / CGFloat(UInt32.max)
    }
}

struct HeroKeyCap: View {
    let label: String
    var down = false
    @State private var hover = false

    var body: some View {
        Text(label)
            .appType(.label)
            .foregroundStyle(Tok.keycapText)
            .frame(width: 48, height: 32)
            .background(down ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control,
                        in: .rect(cornerRadius: Radius.field, style: .continuous))
            .offset(y: down ? 3 : 0)
            .animation(.snappy(duration: 0.12), value: down)
            .animation(Motion.hoverIn, value: hover)
            .background {
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .fill(Tok.well)
                    .offset(y: 3)
            }
            .padding(.bottom, 3)
            .onHover { hover = $0 }
    }
}

/// Step one. The key is the control: press and hold it (or hold the real key) and
/// the blue print head fills; release and the line types itself.
struct FnDemo: View {
    var key: DictationKey = .fn
    @State private var stage = StageModel()
    @State private var down = false
    @State private var typed = 0
    @State private var hasTyped = false
    @State private var didAutoplay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sentence = "The budget is $12,000, and we meet on Tuesday at 3 PM."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.md) {
                keyTarget
                Text("Hold, speak, release.")
                    .appType(.reading)
                    .foregroundStyle(Tok.text)
                    .clearsPixels()
            }

            // The gap and the stage exist only while the key is down, so the block
            // is flush at rest and opens with the animation.
            PixelStage(progress: stage.progress)
                .padding(.top, stage.progress > 0 ? Space.md : 0)

            if hasTyped {
                TypedLine(text: sentence, trigger: typed)
                    .padding(.top, Space.md)
                    .clearsPixels()
            }
        }
        .onKeyChange(key) { isDown in isDown ? press() : release() }
        .task { await autoplayOnce() }
        .onDisappear { stage.reset() }
    }

    private var keyTarget: some View {
        HeroKeyCap(label: key.cap, down: down)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in press() }
                .onEnded { _ in release() })
            .clickable()
            .focusStep(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("\(key.label) key")
            .accessibilityHint("Press and hold to see what Superflow does")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                Task {
                    press()
                    try? await Task.sleep(for: .milliseconds(900))
                    release()
                }
            }
    }

    private func press() {
        guard !down else { return }
        down = true
        stage.press(instantly: reduceMotion)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func release() {
        guard down else { return }
        down = false
        stage.release(instantly: reduceMotion)
        hasTyped = true
        typed += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    /// Teaches the gesture once. A real press cancels it instead of fighting it.
    private func autoplayOnce() async {
        guard !didAutoplay else { return }
        didAutoplay = true
        guard !reduceMotion else {
            hasTyped = true
            typed = 1
            return
        }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, !down else { return }
        press()
        try? await Task.sleep(for: .milliseconds(1_100))
        guard !Task.isCancelled, down else { return }
        release()
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
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .task(id: trigger) {
            guard trigger > 0 else { return }
            count = 0
            if reduceMotion { count = text.count; return }
            caret = true
            try? await Task.sleep(for: .milliseconds(240))
            for line in 1...text.count {
                guard !Task.isCancelled else { return }
                count = line
                try? await Task.sleep(for: .milliseconds(24))
            }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { caret = false }
        }
        .accessibilityLabel(count > 0 ? text : "")
    }
}

@MainActor final class KeyWatcher {
    private var token: Any?
    private var isDown = false
    private var key: DictationKey = .fn

    /// Watches exactly one physical modifier while the onboarding window is
    /// frontmost. A local monitor is enough here: setup runs in the active app,
    /// so this works before Input Monitoring is granted and before the global
    /// hotkey tap starts.
    func start(_ key: DictationKey, _ handler: @escaping @MainActor (Bool) -> Void) {
        stop()
        self.key = key
        token = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.keyCode == self.key.keyCode else { return }
                let down = self.flagDown(event.modifierFlags)
                guard down != self.isDown else { return }
                self.isDown = down
                handler(down)
            }
            return event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        isDown = false
    }

    private func flagDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case .fn: flags.contains(.function)
        case .rightOption, .leftOption: flags.contains(.option)
        case .rightShift: flags.contains(.shift)
        case .rightControl: flags.contains(.control)
        }
    }
}

private struct KeyMonitor: ViewModifier {
    let key: DictationKey
    let perform: @MainActor (Bool) -> Void
    @State private var watcher = KeyWatcher()

    func body(content: Content) -> some View {
        content.onAppear { watcher.start(key, perform) }.onDisappear { watcher.stop() }
    }
}

extension View {
    /// `perform(true)` while the chosen modifier is held, `perform(false)` on release.
    func onKeyChange(_ key: DictationKey,
                     _ perform: @escaping @MainActor (Bool) -> Void) -> some View {
        modifier(KeyMonitor(key: key, perform: perform))
    }
}
