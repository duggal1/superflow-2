import Accelerate
import AVFoundation
import Foundation
import os
import SuperflowDesignSystem
import SwiftUI

enum TapeMetrics {
    static let cell: CGFloat = 4, gap: CGFloat = 2, pitch: CGFloat = 6
    static let half = 3                       // 7 rows
    static let height: CGFloat = 40           // 7 * 6 - 2
}

/// Tenths, floored: 59.96 s never prints 0:60.0.
public enum ClipClock {
    public static func format(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00.0" }
        let n = max(0, Int((t * 10).rounded(.down)))
        return String(format: "%d:%02d.%d", n / 600, (n / 10) % 60, n % 10)
    }
}

// MARK: decode (samples only: no spectrogram, so Play starts instantly)

/// Decodes only what the tape needs. A hover starts the decode, so the click
/// that follows usually has the clip in memory already.
public enum RowClipLoader {
    private final class Box {
        let clip: ClipData
        init(_ clip: ClipData) { self.clip = clip }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSURL, Box> = {
        let cache = NSCache<NSURL, Box>()
        cache.totalCostLimit = 64_000_000
        return cache
    }()

    public static func peek(_ url: URL) -> ClipData? {
        cache.object(forKey: url as NSURL)?.clip
    }

    /// Call on hover: by the time you click, the clip is already in memory.
    public static func preload(_ url: URL) {
        if peek(url) == nil { Task { _ = await load(url) } }
    }

    public static func load(_ url: URL) async -> ClipData? {
        if let hit = peek(url) { return hit }
        let clip = await Task.detached(priority: .userInitiated) { decode(url) }.value
        if let clip { cache.setObject(Box(clip), forKey: url as NSURL, cost: clip.samples.count * 4) }
        return clip
    }

    nonisolated private static func decode(_ url: URL) -> ClipData? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              Double(file.length) <= file.processingFormat.sampleRate * 1_200,        // 20 min cap
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard !samples.isEmpty else { return nil }
        let rate = file.processingFormat.sampleRate
        return ClipData(url: url, samples: samples, sampleRate: rate,
                        duration: Double(samples.count) / rate, frames: 0, cells: [])
    }
}

// MARK: peaks -> cached paths

enum TapePeaks {
    /// One half-height (0...3) per column. Max-pooled, dB-mapped so quiet speech
    /// still lights a cell.
    static func heights(_ samples: [Float], columns: Int) -> [UInt8] {
        guard columns > 0, !samples.isEmpty else { return [] }
        var out = [UInt8](repeating: 0, count: columns)
        samples.withUnsafeBufferPointer { p in
            for c in 0..<columns {
                let lo = c * p.count / columns
                let hi = max(lo + 1, (c + 1) * p.count / columns)
                var peak: Float = 0
                vDSP_maxmgv(p.baseAddress! + lo, 1, &peak, vDSP_Length(hi - lo))
                let level = min(1, max(0, (20 * log10(max(peak, 0.000001)) + 54) / 48))
                out[c] = level < 0.04 ? 0 : UInt8(min(3, Int((level * 3.15).rounded(.up))))
            }
        }
        return out
    }
}

/// Built once per (clip, width). Drawing a frame is a handful of fills of these
/// paths, clipped.
final class WavePaths: @unchecked Sendable {
    let width: CGFloat
    let all: Path, core: Path, tips: Path, coreEven: Path, coreOdd: Path

    init(heights: [UInt8]) {
        let pitch = TapeMetrics.pitch, cell = TapeMetrics.cell, mid = TapeMetrics.half
        var all = Path(), core = Path(), tips = Path(), even = Path(), odd = Path()
        for (c, h) in heights.enumerated() {
            let hh = Int(h)
            for r in (mid - hh)...(mid + hh) {
                let rect = CGRect(x: CGFloat(c) * pitch, y: CGFloat(r) * pitch,
                                  width: cell, height: cell)
                all.addRect(rect)
                if abs(r - mid) == hh { tips.addRect(rect) }                    // the bright outer cell
                else {
                    core.addRect(rect)
                    if (c + r) % 2 == 0 { even.addRect(rect) } else { odd.addRect(rect) }
                }
            }
        }
        self.all = all
        self.core = core
        self.tips = tips
        coreEven = even
        coreOdd = odd
        width = max(0, CGFloat(heights.count) * pitch - TapeMetrics.gap)
    }
}

/// Dead-reckons at 1x between audio-clock updates, then slews toward the sample
/// clock. Audio time arrives in roughly 10 ms steps; the line moves every frame.
@MainActor
final class PlayheadSmoother {
    private var value: TimeInterval = 0
    private var lastWall: TimeInterval = 0

    func step(now: TimeInterval, reported: TimeInterval, playing: Bool) -> TimeInterval {
        guard playing, lastWall != 0 else {
            value = reported
            lastWall = playing ? now : 0
            return value
        }
        let dt = min(0.05, now - lastWall)
        lastWall = now
        value += dt
        let err = reported - value
        if abs(err) > 0.06 { value = reported } else { value += err * 0.12 }
        return value
    }
}

#if DEBUG
/// Logs average fps and the worst frame once a second while playing. Verify
/// 60–120 with this, not by eye.
@MainActor
final class FrameProbe {
    private let log = Logger(subsystem: "com.superflow.app", category: "wave-tape")
    private var last: TimeInterval = 0
    private var mark: TimeInterval = 0
    private var worst: TimeInterval = 0
    private var n = 0

    func tick(_ now: TimeInterval) {
        defer { last = now }
        guard last != 0 else { mark = now; return }
        n += 1
        worst = max(worst, now - last)
        if now - mark >= 1 {
            let fps = Double(n) / (now - mark)
            let worstMs = worst * 1000
            log.debug("WaveTape \(fps, format: .fixed(precision: 1)) fps, worst \(worstMs, format: .fixed(precision: 1)) ms")
            mark = now
            n = 0
            worst = 0
        }
    }
}
#endif

// MARK: the tape

private struct PathKey: Hashable {
    var url: URL?
    var cols: Int
}

public struct WaveTape: View {
    let clip: ClipData?
    let unavailable: Bool
    let player: ClipPlayer
    @Binding var hover: TimeInterval?
    var onTouch: () -> Void = {}

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var width: CGFloat = 0
    @State private var paths: WavePaths?
    @State private var reveal: CGFloat = 0
    @State private var scrubbing = false
    @State private var smoother = PlayheadSmoother()
    #if DEBUG
    @State private var probe = FrameProbe()
    #endif

    public init(clip: ClipData?, unavailable: Bool, player: ClipPlayer,
                hover: Binding<TimeInterval?>, onTouch: @escaping () -> Void = {}) {
        self.clip = clip
        self.unavailable = unavailable
        self.player = player
        _hover = hover
        self.onTouch = onTouch
    }

    private var cols: Int { max(0, Int((width + TapeMetrics.gap) / TapeMetrics.pitch)) }

    public var body: some View {
        let _ = player.moves                                          // redraw after a seek while paused
        let running = player.state == .playing || scrubbing
        let paths = paths, duration = clip?.duration ?? 0, hover = hover, reveal = reveal, scale = scale
        TimelineView(.animation(paused: !running)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let played = smoother.step(now: now, reported: player.time,
                                       playing: player.state == .playing)
            #if DEBUG
            let _ = probe.tick(now)
            #endif
            Canvas { context, size in
                Self.draw(&context, size, paths: paths, duration: duration, played: played,
                          hover: hover, reveal: reveal, scale: scale)
            }
        }
        .frame(height: TapeMetrics.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay { if unavailable { Text("Audio unavailable").appType(.caption).foregroundStyle(Tok.text2) } }
        .contentShape(.rect)
        .gesture(scrub)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): self.hover = clip == nil ? nil : time(at: p.x)
            case .ended: self.hover = nil
            }
        }
        .task(id: PathKey(url: clip?.url, cols: cols)) { await build() }
        .clickable(clip != nil)
        .accessibilityElement()
        .accessibilityLabel("Recording")
        .accessibilityValue(ClipClock.format(player.time))
        .accessibilityAdjustableAction { direction in
            player.seek(player.time + (direction == .increment ? 1 : -1))
        }
        .pixelAudit("WaveTape")
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard clip != nil else { return }
                if !scrubbing {
                    scrubbing = true
                    onTouch()
                    player.beginScrub()
                }
                player.scrub(to: time(at: gesture.location.x))     // tape-head grain under the pointer
            }
            .onEnded { _ in
                guard scrubbing else { return }
                scrubbing = false
                player.endScrub()
            }
    }

    private func time(at x: CGFloat) -> TimeInterval {
        guard let clip, let w = paths?.width ?? Optional(width), w > 0 else { return 0 }
        return min(max(x / w, 0), 1) * clip.duration
    }

    private func build() async {
        guard let clip, cols > 0 else { paths = nil; reveal = 0; return }
        let samples = clip.samples, n = cols
        let built = await Task.detached(priority: .userInitiated) {
            WavePaths(heights: TapePeaks.heights(samples, columns: n))
        }.value
        guard !Task.isCancelled else { return }
        let first = paths == nil
        paths = built
        guard first else { return }
        guard !reduce else { reveal = 1; return }
        reveal = 0                                                      // the tape rolls out in 14 whole steps
        for k in 1...14 {
            try? await Task.sleep(for: .milliseconds(19))
            if Task.isCancelled { return }
            reveal = CGFloat(k) / 14
        }
    }

    // MARK: drawing. No per-cell work: 7 fills of cached paths.

    private static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, paths: WavePaths?,
                             duration: TimeInterval, played: TimeInterval, hover: TimeInterval?,
                             reveal: CGFloat, scale: CGFloat) {
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let h = TapeMetrics.height
        guard let p = paths, duration > 0 else {                        // dormant: a dotted midline
            var x: CGFloat = 0
            while x + TapeMetrics.cell <= size.width {
                ctx.fill(Path(CGRect(x: x, y: CGFloat(TapeMetrics.half) * TapeMetrics.pitch,
                                     width: TapeMetrics.cell, height: TapeMetrics.cell)),
                         with: .color(Tok.controlPressed),
                         style: FillStyle(antialiased: false))
                x += TapeMetrics.pitch
            }
            return
        }
        let w = p.width
        let beam = snap(min(w, max(0, CGFloat(played / duration) * w)))
        ctx.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: snap(w * reveal), height: h)))
            layer.fill(p.all, with: .color(Tok.controlPressed),
                       style: FillStyle(antialiased: false))                 // unplayed
            guard beam > 0 else { return }
            let tail = min(8, beam), head = min(4, beam)
            layer.drawLayer { section in                                 // played: core blue, tips light blue
                section.clip(to: Path(CGRect(x: 0, y: 0, width: beam - tail, height: h)))
                section.fill(p.core, with: .color(Ramp.blue[3]), style: FillStyle(antialiased: false))
                section.fill(p.tips, with: .color(Ramp.blue[4]), style: FillStyle(antialiased: false))
            }
            layer.drawLayer { section in                                 // cooling trail: checker dither
                section.clip(to: Path(CGRect(x: beam - tail, y: 0, width: tail, height: h)))
                section.fill(p.coreEven, with: .color(Ramp.blue[4]), style: FillStyle(antialiased: false))
                section.fill(p.coreOdd, with: .color(Ramp.blue[3]), style: FillStyle(antialiased: false))
                section.fill(p.tips, with: .color(Ramp.blue[4]), style: FillStyle(antialiased: false))
            }
            layer.drawLayer { section in                                 // head: the newest tips go white
                section.clip(to: Path(CGRect(x: beam - head, y: 0, width: head, height: h)))
                section.fill(p.tips, with: .color(Tok.text), style: FillStyle(antialiased: false))
            }
            layer.fill(Path(CGRect(x: min(beam, max(0, w - 1)), y: 0, width: 1, height: h)),
                       with: .color(Tok.text), style: FillStyle(antialiased: false))   // the scan line
        }
        if let hv = hover {                                             // ghost line: where a click would land
            let x = snap(min(max(0, w - 1), hv / duration * w))
            if abs(x - beam) > 2 {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: h)),
                         with: .color(Tok.text2), style: FillStyle(antialiased: false))
            }
        }
    }
}
