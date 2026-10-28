//  SuperflowWaveform.swift
//
//  The app's only waveform. It draws the Island while Fn is held (listening) and
//  while cleanup runs (processing), and it backs every other waveform in the app.
//  Blue 600 / Blue 700. Rounded caps. Whole device pixels. No gradients, no glow,
//  no shadow.
//
//  It does not own the microphone. The audio consumer pushes levels in; this file
//  only draws.
//
//  Island usage:
//      WaveformView(engine: vm.waveform, phase: vm.waveformPhase)
//
//  Static history (Island/Meetings snapshots):
//      LevelsWaveform(levels: model.levels)
//
//  Feeding (from the consumer task that drains the ring buffer, NOT the audio
//  render callback):
//      buffer.withUnsafeBufferPointer { engine.push(samples: $0) }
//      // or, if you already compute RMS: engine.push(level: WaveformEngine.normalized(rms: rms))

import Accelerate
import os
import SuperflowDesignSystem
import SwiftUI

// MARK: - Types

public enum WaveformPhase: Equatable, Sendable {
    /// dots on a line
    case idle
    /// live level
    case listening
    /// calm breathing wave, no input
    case processing
}

public enum WaveformFlow: Sendable {
    /// newest level at the center, older levels travel out both sides
    case outward
    /// newest level on the right, older levels travel left
    case scrolling
}

// MARK: - Engine (state + smoothing, no UI)

public final class WaveformEngine: @unchecked Sendable {
    // Input side: any thread. Peak since the last read, so short syllables are never skipped.
    private struct Inbox {
        var peak: Float = 0
        var latest: Float = 0
        var fresh = false
    }

    private let inbox = OSAllocatedUnfairLock(initialState: Inbox())

    // Render side: only touched from the TimelineView/Canvas render pass.
    private var history: [Float]
    private var shown: [Float] = []
    private var epoch: TimeInterval = 0
    private var lastNow: TimeInterval = 0
    private var tickClock: TimeInterval = 0
    private var lastPhase: WaveformPhase = .idle
    private let step: TimeInterval = 1.0 / 30.0 // one history slot per 33 ms

    public init(historyCapacity: Int = 96) {
        history = Array(repeating: 0, count: max(8, historyCapacity))
    }

    // MARK: Feed

    /// Normalized level, 0...1.
    public func push(level: Float) {
        let value = max(0, min(1, level))
        inbox.withLock { (state: inout Inbox) in
            state.peak = state.fresh ? max(state.peak, value) : value
            state.latest = value
            state.fresh = true
        }
    }

    /// Mono Float samples. Computes RMS with vDSP, then normalizes.
    public func push(samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress, samples.count > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        push(level: Self.normalized(rms: rms))
    }

    /// dBFS window -52...-14 mapped to 0...1. Speech at a normal distance lands around 0.5...0.9.
    public static func normalized(rms: Float, floorDB: Float = -52,
                                  ceilDB: Float = -14, sensitivity: Float = 1) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = max(0, min(1, (db - floorDB) / (ceilDB - floorDB)))
        return min(1, pow(normalized, 0.85) * sensitivity)
    }

    /// Seeds the visible history from an existing snapshot. Used by callers that
    /// already own the level stream (Island, Meetings) instead of a live engine.
    public func seed(_ levels: [Float]) {
        guard !levels.isEmpty else { return }
        let values = levels.suffix(history.count).map { max(0, min(1, $0)) }
        for (offset, value) in values.enumerated() {
            history[offset] = value
        }
        for index in values.count..<history.count {
            history[index] = 0
        }
    }

    // MARK: Render

    /// Returns `count` bar values in 0...1, already smoothed.
    public func frame(now: TimeInterval, phase: WaveformPhase, count: Int,
                      flow: WaveformFlow, calm: Bool) -> [Float] {
        if epoch == 0 { epoch = now }
        let dt = lastNow == 0 ? step : min(0.1, max(0, now - lastNow))
        lastNow = now
        let time = Float(now - epoch)

        if phase != lastPhase {
            if phase == .listening {
                for index in history.indices { history[index] = 0 }
                inbox.withLock { (state: inout Inbox) in state = Inbox() }
                tickClock = 0
            }
            lastPhase = phase
        }

        if phase == .listening {
            tickClock += dt
            var ticks = 0
            while tickClock >= step, ticks < 4 {
                tickClock -= step
                ticks += 1
                let value = inbox.withLock { (state: inout Inbox) -> Float in
                    if state.fresh {
                        state.fresh = false
                        return state.peak
                    }
                    return state.latest
                }
                history.insert(value, at: 0)
                history.removeLast()
            }
            if ticks == 4 { tickClock = 0 }
        } else {
            tickClock = 0
        }

        if shown.count != count { shown = Array(repeating: 0, count: count) }
        let center = Float(count - 1) / 2
        // Fast while following speech so the outward flow stays crisp; slow when changing state so it morphs.
        let (attack, release): (Float, Float) = phase == .listening ? (0.025, 0.09) : (0.12, 0.18)

        for index in 0..<count {
            let distance = abs(Float(index) - center)
            let edge = center > 0 ? distance / center : 0
            var target: Float = 0
            switch phase {
            case .idle:
                target = 0
            case .listening:
                let slot = flow == .outward ? Int(distance) : count - 1 - index
                let taper: Float = flow == .outward ? 1 - 0.35 * edge : 1
                target = history[min(slot, history.count - 1)] * taper
            case .processing:
                let position = center > 0 ? (Float(index) - center) / center : 0
                let wave: Float = calm ? 0
                    : sin(time * 1.5 + position * 3) * 0.25
                    + sin(time * 0.8 - position * 2) * 0.2
                    + cos(time * 2 + position) * 0.15
                target = max(0.05, 0.2 + wave) * (1 - 0.4 * abs(position))
            }
            let tau = target > shown[index] ? attack : release
            shown[index] += (target - shown[index]) * (1 - exp(-Float(dt) / tau))
        }
        return shown
    }
}

// MARK: - View

public struct WaveformView: View {
    private let engine: WaveformEngine
    private let phase: WaveformPhase
    private let flow: WaveformFlow
    private let barWidth: CGFloat
    private let barGap: CGFloat
    private let fadeWidth: CGFloat
    private let height: CGFloat

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var running = true

    public init(engine: WaveformEngine, phase: WaveformPhase,
                flow: WaveformFlow = .outward, barWidth: CGFloat = 3,
                barGap: CGFloat = 2, fadeWidth: CGFloat = 24, height: CGFloat = 28) {
        self.engine = engine
        self.phase = phase
        self.flow = flow
        self.barWidth = barWidth
        self.barGap = barGap
        self.fadeWidth = fadeWidth
        self.height = height
    }

    public var body: some View {
        let scale = scale
        let calm = reduceMotion
        let engine = engine
        let phase = phase
        let flow = flow
        let barWidth = barWidth
        let barGap = barGap
        let fadeWidth = fadeWidth

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(&context, size, now: now, engine: engine, phase: phase, flow: flow,
                          barWidth: barWidth, gap: barGap, fade: fadeWidth,
                          scale: scale, calm: calm)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(label)
        // Stop the render loop 700 ms after going idle (long enough for the bars to settle into dots).
        .task(id: phase) {
            if phase == .idle {
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { running = false }
            } else {
                running = true
            }
        }
    }

    private var label: String {
        switch phase {
        case .idle: "Audio idle"
        case .listening: "Listening"
        case .processing: "Processing audio"
        }
    }

    nonisolated private static func draw(
        _ context: inout GraphicsContext, _ size: CGSize, now: TimeInterval,
        engine: WaveformEngine, phase: WaveformPhase, flow: WaveformFlow,
        barWidth: CGFloat, gap: CGFloat, fade: CGFloat, scale: CGFloat, calm: Bool
    ) {
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        func smooth(_ value: CGFloat) -> CGFloat { value * value * (3 - 2 * value) }

        let width = max(1 / scale, snap(barWidth))
        let spacing = snap(gap)
        let pitch = width + spacing
        let count = max(1, Int((size.width + spacing) / pitch))
        let used = CGFloat(count) * pitch - spacing
        let originX = snap((size.width - used) / 2)
        let bars = engine.frame(now: now, phase: phase, count: count, flow: flow, calm: calm)

        let midY = size.height / 2
        let center = CGFloat(count - 1) / 2

        for index in 0..<count {
            let value = CGFloat(bars[index])

            // A resting bar is a perfect dot (height == width). Height is an even number of
            // device pixels so every bar centers exactly on the pixel grid.
            var barHeight = max(width, value * size.height * 0.86)
            barHeight = (barHeight * scale / 2).rounded() * 2 / scale
            let x = originX + CGFloat(index) * pitch
            let y = snap(midY - barHeight / 2)

            // Edge fade: opacity by distance to the nearest edge. No gradient anywhere.
            let edge = min(x - originX, used - (x - originX) - width)
            context.opacity = fade > 0 ? Double(smooth(min(1, max(0, edge / fade)))) : 1

            // Two flat tones stepped by age: newest = Blue 600, oldest = Blue 700,
            // alternating bars at the seam (the same checker idea as the pixel field).
            let age: CGFloat = flow == .outward
                ? abs(CGFloat(index) - center) / max(center, 1)
                : CGFloat(count - 1 - index) / CGFloat(max(count - 1, 1))
            let tone: Color =
                age < 0.5 ? Tok.accent
                : age < 0.7 ? (index % 2 == 0 ? Tok.accent : Tok.accentPressed)
                : Tok.accentPressed

            let bar = Path(roundedRect: CGRect(x: x, y: y, width: width, height: barHeight),
                           cornerRadius: width / 2, style: .continuous) // full round caps
            context.fill(bar, with: .color(tone))
        }
    }
}

/// Snapshot waveform for callers that already own a level stream (the Island and
/// the Meetings page). It feeds the one engine, so there is one drawing path.
public struct LevelsWaveform: View {
    private let levels: [Float]
    private let barWidth: CGFloat
    private let spacing: CGFloat
    @State private var engine = WaveformEngine()

    public init(levels: [Float], barWidth: CGFloat = 2, spacing: CGFloat = 2) {
        self.levels = levels
        self.barWidth = barWidth
        self.spacing = spacing
    }

    public var body: some View {
        WaveformView(engine: engine, phase: levels.isEmpty ? .idle : .listening,
                     barWidth: barWidth, barGap: spacing, fadeWidth: 8)
            .onAppear { engine.seed(levels) }
            .onChange(of: levels) { _, updated in
                engine.seed(updated)
                if let latest = updated.last { engine.push(level: latest) }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Preview (fake speech so you can judge the motion without a mic)

#if DEBUG
private struct WaveformPreview: View {
    @State private var engine = WaveformEngine()
    @State private var phase: WaveformPhase = .listening

    var body: some View {
        VStack(spacing: 24) {
            WaveformView(engine: engine, phase: phase)
                .frame(width: 180)
            Text("Click to cycle: listening, processing, idle")
                .appType(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(Tok.bg)
        .onTapGesture {
            switch phase {
            case .listening: phase = .processing
            case .processing: phase = .idle
            case .idle: phase = .listening
            }
        }
        .task {
            var time: Float = 0
            while !Task.isCancelled {
                time += 0.023
                let syllable = max(0, sin(time * 7)) * (0.55 + 0.45 * sin(time * 1.3))
                engine.push(level: min(1, syllable * 0.9 + Float.random(in: 0...0.04)))
                try? await Task.sleep(for: .milliseconds(23))
            }
        }
    }
}

#Preview("Waveform") { WaveformPreview() }
#endif
