import AppKit
import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// The Island's public root, unchanged in name so `IslandPanelController` keeps
/// compiling. The body is the rebuilt UI: one silhouette driven by the pure flow
/// state machine. `IslandModel` remains the backend seam the app writes to; this
/// root translates its phase into the new state and renders from there.
public struct IslandRoot: View {
    private let model: IslandModel
    @State private var store: IslandFlowStore
    @State private var intelligence: any IslandIntelligenceSeam = LocalIntelligenceSeam()

    public init(model: IslandModel) {
        self.model = model
        // Seed from the backend on mount: a snapshot renderer (or any first
        // frame) must show the right state without waiting for onChange.
        _store = State(initialValue: IslandFlowStore(Self.externalState(for: model)))
    }

    public var body: some View {
        let state = store.state
        let flowBox = IslandFlowMetrics.box(state,
                                        notchWidth: model.geometry.notch.width,
                                        band: model.geometry.band,
                                        hasNotch: model.geometry.hasNotch,
                                        alwaysOn: model.prefs.alwaysOn,
                                        liveText: model.prefs.liveText && !model.live.text.isEmpty)
        let context = context(for: state)
        let expandedMeeting = model.phase == .meetingPanel && context.hostedView != nil
        let box = expandedMeeting
            ? IslandFlowMetrics.box(.compose(draft: ""), notchWidth: model.geometry.notch.width,
                                    band: model.geometry.band, hasNotch: model.geometry.hasNotch)
            : flowBox
        IslandShell(box: box, stageID: expandedMeeting ? "meeting-assistant" : state.stageID,
                    clickable: clickable(state), clickLabel: "Open Superflow",
                    onHover: { model.hoverChanged($0) },
                    onClick: { model.send(.notchClicked) },
                    hitRect: { model.hitRect = $0 }) { _ in
            if let hosted = context.hostedView {
                hosted.padding(.top, model.geometry.band)
            } else {
                FlowContent(state: state, context: context)
            }
        }
        .environment(\.appTypeScope, .island)
        .fontSmoothing()
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onChange(of: Self.externalState(for: model)) { _, new in
            // Closing the backing panel must close the rendered surface as well.
            store.replace(new)
        }
    }

    // MARK: backend → flow

    private static func externalState(for model: IslandModel) -> IslandFlowState {
        let status = model.assistantStatus
        switch model.phase {
        case .idle, .hover, .notice, .landed:
            return .collapsed
        case .undo(let undo):
            return .undo(text: undo.text)
        case .listening, .handsFree:
            return .listening(target: model.target?.name)
        case .meeting, .meetingPanel:
            return .meetingLive(elapsed: model.elapsed)
        case .processing:
            return .thinking(query: "")
        case .assistant:
            switch status {
            case .idle:
                return .compose(draft: "")
            case .thinking:
                return .thinking(query: "")
            case .streaming, .done, .truncated:
                return .answer(text: model.assistantAnswer, streaming: status == .streaming)
            case .failed(let message):
                return .error(message: message)
            }
        case .history, .recent:
            return .history(count: model.history.count)
        case .failed:
            return .error(message: "Couldn't paste. The transcript is ready to copy.")
        }
    }

    private static func isRestLike(_ state: IslandFlowState) -> Bool {
        switch state {
        case .collapsed, .listening, .meetingLive, .history, .undo: true
        case .compose, .thinking, .answer, .meetingEnded, .settings, .error, .permission: false
        }
    }

    // MARK: flow → views

    @MainActor
    private func context(for state: IslandFlowState) -> FlowContext {
        var ctx = FlowContext()
        ctx.meter = model.meter
        ctx.live = model.prefs.liveText ? model.live.text : ""
        ctx.target = model.target?.name
        ctx.history = model.history
        ctx.theme = IslandTokens.Theme.normal.rawValue
        ctx.seam = intelligence
        ctx.hostedView = model.intelligenceContent?(state)

        var content = IslandIntelligenceContent()
        content.answer = model.assistantAnswer
        content.isStreaming = model.assistantStatus == .streaming
        content.suggestions = suggestions(for: state)
        ctx.intelligence = content

        var actions = FlowActions()
        actions.send = { query in
            store.apply(.submitted(query))
            model.assistantHelp()
        }
        actions.askQuestion = { query in store.apply(.asked(query)) }
        actions.suggestion = { query in
            store.apply(.asked(query))
            model.assistantHelp()
        }
        actions.copyAnswer = copyToPasteboard(model.assistantAnswer)
        actions.copyTranscript = { transcript in model.copy(transcript) }
        actions.startListening = { store.apply(.startedListening(model.target?.name)) }
        actions.openSettings = { store.apply(.openedSettings(theme: IslandTokens.Theme.normal.rawValue)) }
        actions.openHistory = { store.apply(.openedHistory(count: model.history.count)) }
        actions.dismiss = {
            store.apply(.dismissed)
            if case .settings = state { /* a local card; no backend dismissal */ }
            else { model.send(.dismissed) }
        }
        actions.openPermissionSettings = { model.assistantOpenSettings() }
        actions.retry = { model.assistantRetry() }
        actions.theme = { store.apply(.themeChanged($0)) }
        actions.endMeeting = { model.endMeeting() }
        ctx.actions = actions
        return ctx
    }

    /// Suggestions are owned by the Intelligence backend. Until that module is
    /// wired, the meeting-ended card carries an honest empty set rather than
    /// inventing questions the backend never generated.
    private func suggestions(for state: IslandFlowState) -> [String] {
        if case .meetingEnded(let items) = state { return items }
        return []
    }

    private func copyToPasteboard(_ text: String) -> () -> Void {
        {
            guard !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    /// Rest is clickable on a notch; a live capture never opens a card by click.
    private func clickable(_ state: IslandFlowState) -> Bool {
        switch state {
        case .collapsed: model.geometry.hasNotch || model.prefs.alwaysOn
        case .meetingLive: model.phase == .meeting || (model.phase == .meetingPanel && model.intelligenceContent == nil)
        case .listening, .compose, .thinking, .answer, .meetingEnded, .history,
             .undo, .settings, .error, .permission: false
        }
    }
}
