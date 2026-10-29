import Observation
import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// Exact critically damped solution, so there is no integration error and no
/// overshoot. A retarget only moves `target`, never `x` or `v`.
struct Spring1 {
    var x: Double
    var v = 0.0
    var target: Double

    init(_ x: Double) {
        self.x = x
        target = x
    }

    mutating func step(_ dt: Double, omega w: Double) {
        let distance = x - target
        let decay = exp(-w * dt)
        let rate = v + w * distance
        x = target + (distance + rate * dt) * decay
        v = (v - w * rate * dt) * decay
    }

    var settled: Bool { abs(x - target) < 0.004 && abs(v) < 0.02 }

    mutating func land() {
        x = target
        v = 0
    }
}

/// Width leads and height follows; that lag is the wave. The radii settle
/// fastest. Tune these numbers, not the integrator.
struct IslandOmegas {
    var w: Double
    var h: Double
    var r: Double
}

enum IslandMotion {
    static func omegas(from a: IslandBox, to b: IslandBox, band: CGFloat) -> IslandOmegas {
        let small = Double(band) + 40
        let h0 = Double(a.body.height)
        let h1 = Double(b.body.height)
        if h1 <= Double(band) + 8 { return .init(w: 20, h: 18, r: 28) }
        if h0 <= small, h1 > small { return .init(w: 15, h: 12, r: 26) }
        if h0 > small, h1 > small { return .init(w: 18, h: 15, r: 26) }
        return .init(w: 30, h: 28, r: 34)
    }
}

/// The four spring channels the silhouette follows. `retarget` reads the
/// current position and velocity, so interrupting a transition never restarts
/// it; `snap` is only for Reduce Motion and first appearance.
final class IslandKinematics {
    struct Frame {
        var width: CGFloat
        var height: CGFloat
        var top: CGFloat
        var bottom: CGFloat
        var settled: Bool
    }

    private var w = Spring1(0)
    private var h = Spring1(0)
    private var t = Spring1(0)
    private var b = Spring1(0)
    private var om = IslandOmegas(w: 30, h: 28, r: 34)
    private var last: TimeInterval?

    init(startingAt box: IslandBox) {
        snap(box)
    }

    func snap(_ box: IslandBox) {
        w = Spring1(Double(box.body.width))
        h = Spring1(Double(box.body.height))
        t = Spring1(Double(box.top))
        b = Spring1(Double(box.bottom))
        last = nil
    }

    func retarget(_ box: IslandBox, band: CGFloat, instant: Bool) {
        if instant {
            snap(box)
            return
        }
        let from = IslandBox(body: .init(width: CGFloat(w.x), height: CGFloat(h.x)),
                             top: CGFloat(t.x), bottom: CGFloat(b.x), opacity: 1)
        om = IslandMotion.omegas(from: from, to: box, band: band)
        w.target = Double(box.body.width)
        h.target = Double(box.body.height)
        t.target = Double(box.top)
        b.target = Double(box.bottom)
    }

    func step(_ now: TimeInterval, scale: CGFloat) -> Frame {
        let dt = last.map { max(0, now - $0) } ?? 0
        last = now
        if dt > 0 {
            w.step(dt, omega: om.w)
            h.step(dt, omega: om.h)
            t.step(dt, omega: om.r)
            b.step(dt, omega: om.r)
        }
        let done = w.settled && h.settled && t.settled && b.settled
        if done {
            w.land()
            h.land()
            t.land()
            b.land()
            last = nil
        }
        // Whole device pixels; the width is even so the silhouette centres
        // exactly on the notch.
        return Frame(width: Pixel.snapEven(CGFloat(w.x), scale),
                     height: Pixel.snap(CGFloat(h.x), scale),
                     top: CGFloat(t.x), bottom: CGFloat(b.x), settled: done)
    }
}

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

/// Owns the "is the spring still moving" flag outside the view struct, so the
/// frame callback can stop the timeline without mutating state during layout.
@MainActor
@Observable
final class IslandStageClock {
    var running = false
    var revision = 0
}

/// The Island's shell: a per-frame spring drives the silhouette, content is laid
/// out once at its final size and revealed by the growing shape.
@MainActor
struct IslandStage<Content: View>: View {
    private let model: IslandModel
    private let content: Content

    @State private var kin: IslandKinematics
    @State private var clock = IslandStageClock()
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(model: IslandModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
        _kin = State(initialValue: IslandKinematics(startingAt: model.box))
    }

    var body: some View {
        let target = model.box
        let stage = model.confirmingDiscard ? IslandStageID.discard : model.phase.stage
        TimelineView(.animation(paused: !clock.running)) { timeline in
            let frame = kin.step(timeline.date.timeIntervalSinceReferenceDate, scale: scale)
            let _ = park(frame.settled)
            let _ = publish(frame)
            let shape = NotchShape(top: frame.top, bottom: frame.bottom)
            let size = CGSize(width: frame.width + 2 * frame.top, height: frame.height)

            ZStack(alignment: .top) {
                shape.fill(Tok.island)
                    .contrastStroke(shape)
                    .opacity(target.opacity)

                content
                    .id(stage)
                    .transition(reduce ? .opacity : .islandContent)
                    .frame(width: target.body.width, height: target.body.height,
                           alignment: .top)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(shape)

                if model.phase == .history || model.phase == .meetingPanel {
                    SurfaceButton("Close panel") { model.send(.notchClicked) }
                        .frame(width: max(64, model.geometry.notch.width), height: model.geometry.band)
                }

                if clickable {
                    SurfaceButton(clickLabel) { model.send(.notchClicked) }
                        .frame(width: size.width, height: size.height)
                        .clipShape(shape)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .contentShape(shape)
            .onHover { model.hoverChanged($0) }
        }
        .frame(width: IslandLayout.canvas.width, height: IslandLayout.canvas.height,
               alignment: .top)
        .onAppear {
            kin.snap(target)
            clock.revision += 1
            clock.running = true
        }
        .onChange(of: target) { _, next in
            kin.retarget(next, band: model.geometry.band, instant: reduce)
            clock.revision += 1
            clock.running = true
        }
        .onChange(of: reduce) { _, enabled in
            guard enabled else { return }
            kin.snap(target)
            clock.revision += 1
            clock.running = true
        }
        .animation(reduce ? nil : Motion.islandIn, value: stage)
    }

    /// Zero cost at rest: once every channel has settled, the timeline pauses.
    private func park(_ settled: Bool) {
        guard settled, clock.running else { return }
        let clock = clock
        let revision = clock.revision
        Task { @MainActor in
            guard revision == clock.revision else { return }
            clock.running = false
        }
    }

    /// `IslandHostingView` reads this: the real, current silhouette rect.
    private func publish(_ frame: IslandKinematics.Frame) {
        let width = frame.width + 2 * frame.top
        model.hitRect = CGRect(x: (IslandLayout.canvas.width - width) / 2, y: 0,
                               width: width, height: frame.height)
    }

    /// Rest is clickable on a notch, and always clickable when the pill is shown
    /// on a display without one.
    private var clickable: Bool {
        switch model.phase {
        case .idle: model.geometry.hasNotch || model.prefs.alwaysOn
        case .hover, .meeting: true
        case .listening, .handsFree, .meetingPanel, .processing, .landed, .undo,
             .failed, .recent, .history, .notice: false
        }
    }

    private var clickLabel: String {
        switch model.phase {
        case .meeting: "Open meeting panel"
        case .idle, .hover:
            model.prefs.alwaysOn ? "Show recent dictations" : "Show last dictation"
        case .listening, .handsFree, .meetingPanel, .processing, .landed, .undo,
             .failed, .recent, .history, .notice:
            "Show last dictation"
        }
    }
}
