import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// The Island. One window, one shape that animates, one retargetable curve.
/// Anchored at y = 0 of the canvas, which is `screen.frame.maxY`.
public struct IslandRoot: View {
    private let model: IslandModel

    public init(model: IslandModel) {
        self.model = model
    }

    public var body: some View {
        IslandStage(model: model) { content }
            .environment(\.appTypeScope, .island)
            .fontSmoothing()
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .listening, .handsFree, .meeting, .processing, .landed:
            WingsContent(model: model)
        case .meetingPanel:
            if model.confirmingDiscard {
                MeetingDiscardCard(model: model)
            } else {
                MeetingPanel(model: model)
            }
        case .failed(let transcript):
            PasteFailedCard(model: model, transcript: transcript)
        case .recent(let transcript):
            CardContent(model: model, kind: .recent, transcript: transcript)
        case .history:
            HistoryPanel(model: model)
        case .undo(let undo):
            UndoContent(model: model, undo: undo)
        case .notice(let notice):
            NoticeContent(model: model, notice: notice)
        case .hover:
            HoverShelf(model: model)
        case .idle:
            IdleMark(model: model)
        }
    }
}
