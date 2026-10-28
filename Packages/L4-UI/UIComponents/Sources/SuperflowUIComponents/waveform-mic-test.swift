//  SuperflowMicTest.swift
//
//  Mic test for onboarding and Settings. A row of dots sits on a baseline. As
//  your voice gets louder the dots fill in left to right: each one grows wider
//  and stretches upward into a pill, Blue 600 when lit, Blue 700 at rest. A
//  peak-hold dot stays up for a moment, then falls. No gradients, no glow, no
//  strokes. Rounded caps, whole device pixels.
//
//  Usage:
//      MicTestView()                                  // owns a real AVAudioEngine tap
//      MicTestView(source: FakeMicLevelSource())      // previews, no permission needed
//
//  Only run the test while no dictation session is recording. The meter and model
//  do not care where the levels come from.

import AVFoundation
import Accelerate
import os
import SuperflowDesignSystem
import SwiftUI

// dBFS window -52...-14 mapped to 0...1 (same curve as the waveform).
private func normalizedLevel(rms: Float) -> Float {
    let floorDB: Float = -52
    let ceilDB: Float = -14
    let db = 20 * log10(max(rms, 1e-6))
    let normalized = max(0, min(1, (db - floorDB) / (ceilDB - floorDB)))
    return pow(normalized, 0.85)
}

// MARK: - Meter state (smoothing + peak hold, no UI)

public final class DotMeterEngine: @unchecked Sendable {
    private struct Inbox {
        var peak: Float = 0
        var latest: Float = 0
        var fresh = false
    }

    private let inbox = OSAllocatedUnfairLock(initialState: Inbox())
    private var level: Float = 0
    private var peak: Float = 0
    private var holdUntil: TimeInterval = 0
    private var lastNow: TimeInterval = 0

    public init() {}

    /// Normalized level, 0...1. Any thread.
    public func push(_ value: Float) {
        let clamped = max(0, min(1, value))
        inbox.withLock { (state: inout Inbox) in
            state.peak = state.fresh ? max(state.peak, clamped) : clamped
            state.latest = clamped
            state.fresh = true
        }
    }

    public func reset() {
        inbox.withLock { (state: inout Inbox) in state = Inbox() }
        level = 0
        peak = 0
        holdUntil = 0
        lastNow = 0
    }

    /// Render thread only. `calm` (Reduce Motion) = raw level, no easing, no peak hold.
    public func frame(now: TimeInterval, active: Bool,
                      calm: Bool) -> (level: Float, peak: Float) {
        let dt = lastNow == 0 ? 1.0 / 30 : min(0.1, max(0, now - lastNow))
        lastNow = now

        var target: Float = 0
        if active {
            target = inbox.withLock { (state: inout Inbox) -> Float in
                if state.fresh {
                    state.fresh = false
                    return state.peak
                }
                return state.latest
            }
        }

        if calm {
            level = target
            peak = 0
        } else {
            let tau: Float = target > level ? 0.03 : 0.2 // snap up, ease down
            level += (target - level) * (1 - exp(-Float(dt) / tau))
            if level >= peak {
                peak = level
                holdUntil = now + 0.55
            } else if now > holdUntil {
                peak = max(level, peak - Float(dt) * 0.9)
            }
        }
        return (level, peak)
    }
}

// MARK: - The dots

struct MicDotMeter: View {
    let meter: DotMeterEngine
    var active: Bool
    var dots = 14
    var dot: CGFloat = 6
    var gap: CGFloat = 6
    var rise: CGFloat = 16

    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var running = true

    private var totalWidth: CGFloat {
        CGFloat(dots) * dot + CGFloat(dots - 1) * gap
    }

    var body: some View {
        let meter = meter
        let active = active
        let count = dots
        let dot = dot
        let gap = gap
        let rise = rise
        let scale = scale
        let calm = reduceMotion
        let dark = scheme == .dark

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(&context, size, now: now, meter: meter, active: active, dots: count,
                          dot: dot, gap: gap, rise: rise, scale: scale, calm: calm, dark: dark)
            }
        }
        .frame(width: totalWidth, height: dot + rise + 2)
        .accessibilityHidden(true) // the status text beside it carries the meaning
        .task(id: active) {
            if active {
                running = true
            } else {
                try? await Task.sleep(for: .milliseconds(700)) // let the dots settle back
                if !Task.isCancelled { running = false }
            }
        }
    }

    nonisolated private static func draw(
        _ context: inout GraphicsContext, _ size: CGSize, now: TimeInterval,
        meter: DotMeterEngine, active: Bool, dots count: Int, dot: CGFloat,
        gap: CGFloat, rise: CGFloat, scale: CGFloat, calm: Bool, dark: Bool
    ) {
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

        let state = meter.frame(now: now, active: active, calm: calm)
        let dotSize = snap(dot)
        let spacing = snap(gap)
        let total = CGFloat(count) * dotSize + CGFloat(count - 1) * spacing
        let originX = snap((size.width - total) / 2)
        let baseline = snap(size.height)
        let peakIndex = state.peak > 0.04 ? min(count - 1, Int(state.peak * Float(count))) : -1

        for index in 0..<count {
            // Dot i fills as the level passes its slot, so the frontier dot is only part grown.
            let raw = max(0, min(1, state.level * Float(count) - Float(index)))
            var amount = CGFloat(raw * raw * (3 - 2 * raw)) // smoothstep
            if index == peakIndex { amount = max(amount, 0.7) } // peak hold

            let width = snap(dotSize + amount * 1.5) // a touch wider
            let height = snap(dotSize + amount * rise) // and taller, anchored at the baseline
            let x = snap(originX + CGFloat(index) * (dotSize + spacing) + (dotSize - width) / 2)
            let lit = amount > 0.04

            context.opacity = lit ? 1 : (dark ? 0.75 : 0.5)
            context.fill(
                Path(roundedRect: CGRect(x: x, y: baseline - height, width: width, height: height),
                     cornerRadius: width / 2, style: .continuous),
                with: .color(lit ? Tok.accent : Tok.accentPressed)
            )
        }
    }
}

// MARK: - Model

@MainActor
@Observable
public final class MicTestModel {
    public enum State: Equatable {
        case idle, requesting, testing, denied, failed(String)
    }

    public enum Signal {
        case waiting, hearing, quiet
    }

    public private(set) var state: State = .idle
    public private(set) var signal: Signal = .waiting

    @ObservationIgnored public let meter = DotMeterEngine()
    @ObservationIgnored private let source: any MicLevelSource
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(source: any MicLevelSource) {
        self.source = source
    }

    public var buttonTitle: String {
        switch state {
        case .idle, .failed: "Test microphone"
        case .requesting: "Starting"
        case .testing: "Stop"
        case .denied: "Open Settings"
        }
    }

    public var message: String {
        switch state {
        case .idle: "Check that Superflow can hear you."
        case .requesting: "Waiting for microphone access."
        case .denied: "Microphone access is off. Allow it in System Settings."
        case .failed(let reason): reason
        case .testing:
            switch signal {
            case .waiting: "Say something."
            case .hearing: "Hearing you."
            case .quiet: "No signal. Check your input device in System Settings."
            }
        }
    }

    public func primaryAction() {
        switch state {
        case .idle, .failed: start()
        case .testing: stop()
        case .denied: Self.openPrivacySettings()
        case .requesting: break
        }
    }

    public func start() {
        guard task == nil else { return }
        state = .requesting
        signal = .waiting
        task = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        let wasActive = task != nil
        task?.cancel()
        task = nil
        if wasActive {
            source.stop()
            meter.reset()
        }
        state = .idle
        signal = .waiting
    }

    private func run() async {
        if source.needsPermission, await Self.hasMicPermission() == false {
            state = .denied
            task = nil
            return
        }
        do {
            let stream = try source.start()
            state = .testing
            let began = ContinuousClock.now
            var lastHeard: ContinuousClock.Instant?

            for await rms in stream {
                let level = normalizedLevel(rms: rms)
                meter.push(level)

                let now = ContinuousClock.now
                if level > 0.14 { lastHeard = now }
                let hearing = lastHeard.map { now - $0 < .milliseconds(1200) } ?? false
                let next: Signal = hearing ? .hearing
                    : (lastHeard == nil && now - began > .seconds(4) ? .quiet : .waiting)
                if signal != next { signal = next } // only publish changes
            }

            // The stream ended on its own: the input device changed or went away.
            if !Task.isCancelled, state == .testing {
                meter.reset()
                state = .failed("The input device changed. Start the test again.")
                task = nil
            }
        } catch {
            meter.reset()
            state = .failed(error.localizedDescription)
            task = nil
        }
    }

    private static func hasMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        if let url { NSWorkspace.shared.open(url) }
    }
}

// MARK: - The component

public struct MicTestView: View {
    @State private var model: MicTestModel

    public init(source: any MicLevelSource = AVMicLevelSource()) {
        _model = State(initialValue: MicTestModel(source: source))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.lg) {
                MicDotMeter(meter: model.meter, active: model.state == .testing)
                AppButton(model.buttonTitle, kind: buttonKind, height: ControlHeight.regular,
                          enabled: model.state != .requesting, action: model.primaryAction)
            }
            Text(model.message)
                .appType(.caption)
                .foregroundStyle(Tok.text2)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.18), value: model.message)
        }
        .onDisappear { model.stop() }
        .accessibilityElement(children: .contain)
    }

    private var buttonKind: ButtonKind {
        switch model.state {
        case .testing: .secondary
        case .denied: .quiet
        default: .primary
        }
    }
}

// MARK: - Preview (simulated voice, no permission prompt)

#if DEBUG
public struct FakeMicLevelSource: MicLevelSource {
    public init() {}

    public var needsPermission: Bool { false }

    public func start() throws -> AsyncStream<Float> {
        AsyncStream { continuation in
            let task = Task {
                var time: Float = 0
                while !Task.isCancelled {
                    time += 0.023
                    let burst = max(0, sin(time * 6)) * (0.55 + 0.45 * sin(time * 1.1))
                    let db = -46 + 30 * burst // -46...-16 dBFS
                    continuation.yield(pow(10, db / 20))
                    try? await Task.sleep(for: .milliseconds(23))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() {}
}

#Preview("Mic test") {
    MicTestView(source: FakeMicLevelSource())
        .padding(Space.xl)
        .frame(width: 440, alignment: .leading)
        .background(Tok.bg)
}
#endif
