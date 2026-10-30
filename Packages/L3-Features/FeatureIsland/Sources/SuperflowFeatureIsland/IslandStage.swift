import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

private struct StageKey: Equatable {
    var scene: IslandScene
    var box: IslandBox
}

private struct Outgoing {
    var scene: IslandScene
    var box: IslandBox
    var generation: Int
}

private func sstep(_ x: Double) -> Double {
    let t = min(1, max(0, x))
    return t * t * (3 - 2 * t)
}

/// The Island's shell: one per-frame spring drives both the silhouette and the
/// content crossfade. Content is laid out once at its final size and revealed by
/// the moving silhouette; no blur, no re-layout during the move.
@MainActor
struct IslandStage<Content: View>: View {
    private let model: IslandModel
    private let content: (IslandScene) -> Content

    @State private var kin: IslandKinematics
    @State private var clock = IslandStageClock()
    @State private var out: Outgoing?
    @State private var crossfade = 0
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce
    #if DEBUG
    @State private var probe = IslandFrameProbe()
    #endif

    init(model: IslandModel, @ViewBuilder content: @escaping (IslandScene) -> Content) {
        self.model = model
        self.content = content
        _kin = State(initialValue: IslandKinematics(startingAt: model.box))
    }

    var body: some View {
        let key = StageKey(scene: model.scene, box: model.box)
        let target = key.box
        let scene = key.scene
        TimelineView(.animation(paused: !clock.running)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let frame = kin.step(now, scale: scale)
            let _ = park(frame)
            let _ = publish(frame)
            #if DEBUG
            let _ = { if clock.running { probe.tick(now) } }()
            #endif
            // Out leaves first and quickly. In follows late and soft. Same clock
            // as the silhouette, so the shape and its content cannot disagree.
            let outA = 1 - sstep(frame.fade / 0.36)
            let inA = sstep((frame.fade - 0.28) / 0.72)
            let shape = NotchShape(top: frame.top, bottom: frame.bottom)
            let size = CGSize(width: frame.width + 2 * frame.top, height: frame.height)

            ZStack(alignment: .top) {
                shape.fill(Tok.island)
                    .contrastStroke(shape)
                    .opacity(target.opacity)

                ZStack(alignment: .top) {
                    if let outgoing = out, frame.fade < 0.999 {
                        content(outgoing.scene)
                            .frame(width: outgoing.box.body.width, height: outgoing.box.body.height,
                                   alignment: .top)
                            .scaleEffect(1 - 0.03 * (1 - outA), anchor: .top)
                            .opacity(outA)
                    }
                    content(scene)
                        .id(scene.stage)
                        .frame(width: target.body.width, height: target.body.height,
                               alignment: .top)   // laid out ONCE, at final size
                        .scaleEffect(0.95 + 0.05 * inA, anchor: .top)
                        .offset(y: 5 * (1 - inA))
                        .opacity(inA)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
                .opacity(target.opacity)

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
            wake()
        }
        .onChange(of: key) { old, new in
            let newStage = old.scene.stage != new.scene.stage
            if newStage && !reduce {
                crossfade &+= 1
                out = Outgoing(scene: old.scene, box: old.box, generation: crossfade)
            } else if reduce {
                out = nil
            }
            kin.retarget(new.box, band: model.geometry.band, instant: reduce, newStage: newStage)
            wake()
        }
        .onChange(of: model.bump) { _, _ in
            guard !reduce else { return }
            kin.bump(width: 3, height: 1.5)
            wake()
        }
        .onChange(of: reduce) { _, enabled in
            guard enabled else { return }
            out = nil
            kin.snap(target)
            wake()
        }
    }

    private func wake() {
        clock.revision += 1
        clock.running = true
    }

    /// Zero cost at rest: once every channel has settled, the timeline pauses.
    /// The fade has already finished by then, so the outgoing layer can go too.
    private func park(_ frame: IslandKinematics.Frame) {
        if frame.fade >= 0.999, let outgoing = out {
            let generation = outgoing.generation
            Task { @MainActor in
                guard out?.generation == generation else { return }
                out = nil
            }
        }
        guard frame.settled, clock.running else { return }
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
