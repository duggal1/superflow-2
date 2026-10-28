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

    private var live: Bool { model.prefs.liveText }

    public var body: some View {
        let box = IslandLayout.box(model.phase, model.geometry,
                                   hint: model.hint, live: live, prefs: model.prefs)
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
                    // One click target for the rest states and for the meeting
                    // wings. It sits above the content, so it opens panels; every
                    // card draws its own controls and is never covered.
                    if clickTarget {
                        SurfaceButton(clickLabel) { model.send(.notchClicked) }
                    }
                }
                .onHover { model.hoverChanged($0) }
        }
        .frame(width: IslandLayout.canvas.width, height: IslandLayout.canvas.height,
               alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// Rest is clickable on a notch, and always clickable when the pill is shown
    /// on a display without one.
    private var clickTarget: Bool {
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

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .listening, .handsFree, .meeting, .processing, .landed:
            WingsContent(model: model)
                .id("wings")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .meetingPanel:
            MeetingPanel(model: model)
                .id("meeting-panel")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .failed(let transcript):
            PasteFailedCard(model: model, transcript: transcript)
                .id("card")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .recent(let transcript):
            CardContent(model: model, kind: .recent, transcript: transcript)
                .id("card")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .history:
            HistoryPanel(model: model)
                .id("history")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .undo(let undo):
            UndoContent(model: model, undo: undo)
                .id("undo")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .notice(let notice):
            NoticeContent(model: model, notice: notice)
                .id("notice")
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .hover:
            HoverShelf(model: model)
                .id("hover")
                .transition(.opacity)
        case .idle:
            IdleMark(model: model)
                .id("idle")
                .transition(.opacity)
        }
    }
}
