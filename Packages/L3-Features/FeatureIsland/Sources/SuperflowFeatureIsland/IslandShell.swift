import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

private func smoothstep(_ x: Double) -> Double {
    let t = min(1, max(0, x))
    return t * t * (3 - 2 * t)
}

private struct StageSnapshot: Equatable {
    var stageID: String
    var box: IslandBox
}

/// The mounted silhouette. One window, one opaque-black shape, flat at the top
/// edge of the screen (`screen.frame.maxY`) and round at the bottom. There is no
/// glass, shadow, border or material. Width, height and both radii are solved
/// by the single motion engine so the shape and its content cannot disagree.
///
/// Content is laid out once at its destination size and revealed by the moving
/// silhouette. With Reduce Motion the geometry snaps and the end state is shown.
@MainActor
struct IslandShell<Content: View>: View {
    private let box: IslandBox
    private let stageID: String
    private let clickable: Bool
    private let clickLabel: String
    private let onHover: (Bool) -> Void
    private let onClick: () -> Void
    private let hitRect: (CGRect) -> Void
    private let content: (String) -> Content

    @State private var kin: IslandKinematics
    @State private var running = false
    @State private var outgoing: StageSnapshot?
    @Environment(\.displayScale) private var scale
    @Environment(\.islandReduceMotion) private var reduce

    init(box: IslandBox, stageID: String, clickable: Bool, clickLabel: String,
         onHover: @escaping (Bool) -> Void, onClick: @escaping () -> Void,
         hitRect: @escaping (CGRect) -> Void,
         @ViewBuilder content: @escaping (String) -> Content) {
        self.box = box
        self.stageID = stageID
        self.clickable = clickable
        self.clickLabel = clickLabel
        self.onHover = onHover
        self.onClick = onClick
        self.hitRect = hitRect
        self.content = content
        _kin = State(initialValue: IslandKinematics(startingAt: box))
    }

    var body: some View {
        let key = StageSnapshot(stageID: stageID, box: box)
        TimelineView(.animation(paused: !running)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            #if DEBUG
            let _ = IslandFrameProbe.shared.tick(now)
            #endif
            let frame = kin.step(now, scale: scale)
            let _ = park(frame)
            let _ = publish(frame)

            let outAlpha = 1 - smoothstep(frame.fade / 0.36)
            let inAlpha = smoothstep((frame.fade - 0.28) / 0.72)
            let shape = NotchShape(top: frame.top, bottom: frame.bottom)
            let size = CGSize(width: frame.width + 2 * frame.top, height: frame.height)

            ZStack(alignment: .top) {
                // The body. Opaque black, no stroke, no shadow, no material.
                shape.fill(IslandTokens.Color.body)
                    .opacity(box.opacity)

                ZStack(alignment: .top) {
                    if let outgoing, frame.fade < 0.999 {
                        content(outgoing.stageID)
                            .frame(width: outgoing.box.body.width,
                                   height: outgoing.box.body.height, alignment: .top)
                            .scaleEffect(1 - 0.03 * (1 - outAlpha), anchor: .top)
                            .opacity(outAlpha)
                    }
                    content(stageID)
                        .id(stageID)
                        .frame(width: box.body.width, height: box.body.height, alignment: .top)
                        .scaleEffect(0.95 + 0.05 * inAlpha, anchor: .top)
                        .offset(y: 5 * (1 - inAlpha))
                        .opacity(inAlpha)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
                .opacity(box.opacity)

                if clickable {
                    SurfaceButton(clickLabel, action: onClick)
                        .frame(width: size.width, height: size.height)
                        .clipShape(shape)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .contentShape(shape)
            .onHover { onHover($0) }
        }
        .frame(width: IslandTokens.Size.canvas.width,
               height: IslandTokens.Size.canvas.height, alignment: .top)
        .onAppear {
            kin.snap(box)
            outgoing = nil
            running = false
        }
        .onChange(of: key) { old, new in
            #if DEBUG
            IslandFrameProbe.shared.restart()
            #endif
            let newStage = old.stageID != new.stageID
            outgoing = (!reduce && newStage) ? old : nil
            kin.retarget(new.box, band: IslandTokens.Size.band, instant: reduce, newStage: newStage)
            running = true
        }
        .onChange(of: reduce) { _, enabled in
            guard enabled else { return }
            outgoing = nil
            kin.snap(box)
            running = true
        }
    }

    /// Zero cost at rest: once every channel has settled the timeline pauses.
    private func park(_ frame: IslandKinematics.Frame) {
        if frame.fade >= 0.999, outgoing != nil {
            let generation = outgoing
            Task { @MainActor in
                guard self.outgoing == generation else { return }
                self.outgoing = nil
            }
        }
        guard frame.settled, running else { return }
        Task { @MainActor in
            guard self.running else { return }
            self.running = false
        }
    }

    /// The host reads this for shape-accurate hit testing.
    private func publish(_ frame: IslandKinematics.Frame) {
        let width = frame.width + 2 * frame.top
        hitRect(CGRect(x: (IslandTokens.Size.canvas.width - width) / 2,
                       y: 0, width: width, height: frame.height))
    }
}
