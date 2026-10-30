import Observation
import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI
#if DEBUG
import os
#endif

// MARK: spring, exact solution (underdamped and critical), so no integration error at any frame rate

/// The closed-form solution of a damped spring. Retargeting only moves `target`;
/// position and velocity survive, so an interrupted transition continues from
/// where it is instead of restarting. Undamped overshoot is controlled by `z`:
/// `1` is critical, below `1` is the small opening overshoot iOS has.
struct Spring1 {
    var x: Double
    var v = 0.0
    var target: Double

    init(_ x: Double) {
        self.x = x
        target = x
    }

    mutating func step(_ dt: Double, omega w: Double, zeta z: Double = 1) {
        let d = x - target
        if z >= 0.999 {
            let e = exp(-w * dt), c = v + w * d
            x = target + (d + c * dt) * e
            v = (v - w * c * dt) * e
        } else {
            let wd = w * (1 - z * z).squareRoot()
            let e = exp(-z * w * dt), cs = cos(wd * dt), sn = sin(wd * dt)
            let nd = e * (d * cs + ((v + z * w * d) / wd) * sn)
            let nv = e * (v * cs - ((w * w * d + z * w * v) / wd) * sn)
            x = target + nd
            v = nv
        }
    }

    var settled: Bool { abs(x - target) < 0.004 && abs(v) < 0.02 }

    mutating func land() {
        x = target
        v = 0
    }
}

struct SpringSpec: Equatable, Sendable {
    var w: Double
    var z: Double
}

struct IslandPreset: Equatable, Sendable {
    var width: SpringSpec
    var height: SpringSpec
    var radius: SpringSpec
    var fade: Double
}

enum IslandMotion {
    // Settle time of a critical spring is about 5.8 / w. Underdamped: about 4 / (z * w).
    // `z` is the damping ratio: 1 is critical, 0.80-0.90 is the small iOS opening
    // overshoot. Closing stays critical, so nothing ever overshoots on the way out.
    static let open = IslandPreset(width: .init(w: 14, z: 0.80), height: .init(w: 12, z: 0.84),
                                   radius: .init(w: 22, z: 1), fade: 15)
    static let close = IslandPreset(width: .init(w: 22, z: 1.00), height: .init(w: 20, z: 1.00),
                                    radius: .init(w: 28, z: 1), fade: 24)
    static let card = IslandPreset(width: .init(w: 18, z: 0.88), height: .init(w: 15, z: 0.90),
                                   radius: .init(w: 24, z: 1), fade: 18)
    static let wings = IslandPreset(width: .init(w: 30, z: 0.86), height: .init(w: 28, z: 0.90),
                                    radius: .init(w: 34, z: 1), fade: 28)

    static func preset(from a: IslandBox, to b: IslandBox, band: CGFloat) -> IslandPreset {
        let small = Double(band) + 40
        let h0 = Double(a.body.height)
        let h1 = Double(b.body.height)
        if h1 <= Double(band) + 8 { return close }
        if h0 <= small, h1 > small { return open }
        if h0 > small, h1 > small { return card }
        return wings
    }
}

/// The five channels the silhouette and its content follow. Every channel is
/// solved at the display rate, so the shape and the crossfade cannot disagree.
final class IslandKinematics {
    struct Frame {
        var width: CGFloat
        var height: CGFloat
        var top: CGFloat
        var bottom: CGFloat
        /// 0...1 content crossfade progress for the current stage.
        var fade: Double
        var settled: Bool
    }

    private var w = Spring1(0)
    private var h = Spring1(0)
    private var t = Spring1(0)
    private var b = Spring1(0)
    private var c = Spring1(1)
    private var preset = IslandMotion.wings
    private var last: TimeInterval?

    init(startingAt box: IslandBox) {
        snap(box)
    }

    func snap(_ box: IslandBox) {
        w = Spring1(Double(box.body.width))
        h = Spring1(Double(box.body.height))
        t = Spring1(Double(box.top))
        b = Spring1(Double(box.bottom))
        c = Spring1(1)
        last = nil
    }

    /// Retargets from the CURRENT position and velocity: interrupting never
    /// restarts a transition. `newStage` restarts the content crossfade only;
    /// the silhouette keeps moving.
    func retarget(_ box: IslandBox, band: CGFloat, instant: Bool, newStage: Bool = false) {
        if instant {
            snap(box)
            return
        }
        let from = IslandBox(body: .init(width: CGFloat(w.x), height: CGFloat(h.x)),
                             top: CGFloat(t.x), bottom: CGFloat(b.x), opacity: 1)
        preset = IslandMotion.preset(from: from, to: box, band: band)
        w.target = Double(box.body.width)
        h.target = Double(box.body.height)
        t.target = Double(box.top)
        b.target = Double(box.bottom)
        if newStage {
            c.x = 0
            c.v = 0
            c.target = 1
        }
        last = nil
    }

    /// A small success nudge, like iOS. `px` and `py` are the peak excursion in
    /// points; tune these two numbers, not the integrator.
    func bump(width px: Double, height py: Double) {
        preset = IslandMotion.wings
        w.v += px * preset.width.w * M_E
        h.v += py * preset.height.w * M_E
        last = nil
    }

    func step(_ now: TimeInterval, scale: CGFloat) -> Frame {
        let dt = last.map { max(0, now - $0) } ?? 0
        last = now
        if dt > 0 {
            w.step(dt, omega: preset.width.w, zeta: preset.width.z)
            h.step(dt, omega: preset.height.w, zeta: preset.height.z)
            t.step(dt, omega: preset.radius.w, zeta: preset.radius.z)
            b.step(dt, omega: preset.radius.w, zeta: preset.radius.z)
            c.step(dt, omega: preset.fade, zeta: 1)
        }
        let done = w.settled && h.settled && t.settled && b.settled && c.settled
        if done {
            w.land()
            h.land()
            t.land()
            b.land()
            c.land()
            last = nil
        }
        // Width even and height whole: the silhouette sits exactly on the device
        // pixel grid.
        return Frame(width: Pixel.snapEven(CGFloat(w.x), scale),
                     height: Pixel.snap(CGFloat(h.x), scale),
                     top: max(0, CGFloat(t.x)), bottom: max(0, CGFloat(b.x)),
                     fade: min(1, max(0, c.x)), settled: done)
    }
}

// MARK: scenes

enum IslandStageID: Hashable, Sendable {
    case rest, listening, processing, landed, cancelled, failed, recent, history
    case meetingWings, meetingPanel, discard
    case notice(Date)
}

extension IslandPhase {
    /// Scenes that share a stage morph in place; a new stage cross-dissolves.
    var stage: IslandStageID {
        switch self {
        case .idle, .hover: .rest
        case .listening, .handsFree: .listening
        case .meeting: .meetingWings
        case .meetingPanel: .meetingPanel
        case .processing: .processing
        case .landed: .landed
        case .undo: .cancelled
        case .failed: .failed
        case .recent: .recent
        case .history: .history
        case .notice(let note): .notice(note.postedAt)
        }
    }
}

/// What the stage renders, captured so the outgoing layer can keep showing the
/// old scene while the incoming one is already mounted.
struct IslandScene: Equatable {
    var phase: IslandPhase
    var confirmingDiscard: Bool

    var stage: IslandStageID {
        confirmingDiscard ? .discard : phase.stage
    }
}

extension IslandModel {
    var scene: IslandScene {
        IslandScene(phase: phase, confirmingDiscard: confirmingDiscard)
    }
}

/// Owns the "is the spring still moving" flag outside the view struct, so the
/// frame callback can stop the timeline without mutating state during layout.
@MainActor
@Observable
final class IslandStageClock {
    var running = false
    var revision = 0
}

#if DEBUG
/// Logs average fps and the worst frame once a second while the Island moves.
@MainActor
final class IslandFrameProbe {
    private let log = Logger(subsystem: "com.superflow.app", category: "island-motion")
    private var last: TimeInterval = 0
    private var mark: TimeInterval = 0
    private var worst: TimeInterval = 0
    private var n = 0

    func tick(_ now: TimeInterval) {
        defer { last = now }
        guard last != 0 else {
            mark = now
            return
        }
        n += 1
        worst = max(worst, now - last)
        if now - mark >= 1 {
            let fps = Double(n) / (now - mark)
            let worstMs = worst * 1000
            log.debug("Island \(fps, format: .fixed(precision: 1)) fps, worst \(worstMs, format: .fixed(precision: 1)) ms")
            mark = now
            n = 0
            worst = 0
        }
    }
}
#endif

// MARK: entrance

/// Critically damped step response with no stored animation state and no blur.
/// Used for things inside one scene, where the stage crossfade is not involved.
struct Entrance: ViewModifier {
    var delay: Double = 0
    var dx: CGFloat = 0
    var dy: CGFloat = 6

    @State private var born = Date()
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        let reduce = reduce
        TimelineView(.animation(paused: done)) { timeline in
            let t = max(0, timeline.date.timeIntervalSince(born) - delay)
            let p = reduce ? 1 : 1 - exp(-18 * t) * (1 + 18 * t)
            let _ = {
                if reduce || t > 0.7 {
                    Task { @MainActor in done = true }
                }
            }()
            content
                .opacity(min(1, p * 1.25))
                .offset(x: dx * (1 - p), y: dy * (1 - p))
        }
    }
}

extension View {
    /// Row `i` of a panel: waits for the silhouette to open, then rises 35 ms
    /// after the row above.
    func islandReveal(_ i: Int) -> some View {
        modifier(Entrance(delay: 0.12 + Double(i) * 0.035, dy: 6))
    }
}
