import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// The Island. One window, one shape that animates, one retargetable curve.
/// Anchored at y = 0 of the canvas, which is `screen.frame.maxY`.
public struct IslandRoot: View {
    private let model: IslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: IslandModel) {
        self.model = model
    }

    public var body: some View {
        let box = IslandLayout.box(model.phase, model.geometry)
        let size = box.frameSize

        ZStack(alignment: .top) {
            NotchShape(top: box.top, bottom: box.bottom)
                .fill(Tok.island)
                .contrastStroke(NotchShape(top: box.top, bottom: box.bottom))
                .frame(width: size.width, height: size.height)
                .opacity(box.opacity)
                .transaction(value: model.phase) { transaction in
                    if reduceMotion { transaction.animation = nil }
                }
                .overlay(alignment: .top) {
                    content
                        .frame(width: box.body.width, height: box.body.height, alignment: .top)
                        .clipShape(NotchShape(top: 0, bottom: box.bottom))
                }
                .overlay {
                    if model.phase.isRest, model.geometry.hasNotch {
                        SurfaceButton("Show last dictation") { model.openRecent() }
                    }
                }
                .onHover { model.hoverChanged($0) }
        }
        .frame(width: IslandLayout.canvas.width, height: IslandLayout.canvas.height,
               alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .listening, .processing, .landed:
            WingsContent(model: model)
                .id("wings")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .failed(let transcript):
            CardContent(model: model, kind: .failed, transcript: transcript)
                .id("card")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .recent(let transcript):
            CardContent(model: model, kind: .recent, transcript: transcript)
                .id("card")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .hover:
            HoverMark()
                .id("hover")
                .transition(.opacity)
        case .idle:
            EmptyView()
        }
    }
}
