import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Everything a flow view may need that is not state. Keeping it in one value
/// makes each state view small and gives the snapshot tests one thing to build.
@MainActor
struct FlowContext {
    var intelligence: IslandIntelligenceContent = .empty
    var meter: IslandMeterModel = IslandMeterModel()
    var live: String = ""
    var target: String?
    var history: [IslandTranscript] = []
    var theme: String = IslandTokens.Theme.normal.rawValue
    var seam: any IslandIntelligenceSeam = LocalIntelligenceSeam()
    /// Optional view supplied by the App-side Intelligence seam. When present it
    /// replaces the local compose/answer presentation without importing another
    /// L3 module.
    var hostedView: AnyView?
    var actions = FlowActions()
}

struct FlowActions {
    var send: (String) -> Void = { _ in }
    var copyAnswer: () -> Void = {}
    var copyTranscript: (IslandTranscript) -> Void = { _ in }
    var startListening: () -> Void = {}
    var openSettings: () -> Void = {}
    var openHistory: () -> Void = {}
    var dismiss: () -> Void = {}
    var openPermissionSettings: () -> Void = {}
    var retry: () -> Void = {}
    var theme: (String) -> Void = { _ in }
    var suggestion: (String) -> Void = { _ in }
    var endMeeting: () -> Void = {}
    var askQuestion: (String) -> Void = { _ in }
}

/// Maps one state to one view. No state is left unhandled, so Reduce Motion can
/// render the final state of any branch without waiting on an animation.
@ViewBuilder
func FlowContent(state: IslandFlowState, context: FlowContext) -> some View {
    switch state {
    case .collapsed:
        CollapsedView()
    case .undo(let text):
        UndoView(text: text, context: context)
    case .compose(let draft):
        ComposeView(draft: draft, context: context)
    case .listening(let target):
        ListeningView(target: target, context: context)
    case .thinking(let query):
        ThinkingView(query: query)
    case .answer(let text, let streaming):
        AnswerView(text: text, streaming: streaming, context: context)
    case .meetingLive(let elapsed):
        MeetingLiveView(elapsed: elapsed, context: context)
    case .meetingEnded(let suggestions):
        MeetingEndedView(suggestions: suggestions, context: context)
    case .history(let count):
        HistoryView(count: count, context: context)
    case .settings(let theme):
        SettingsView(theme: theme, context: context)
    case .error(let message):
        ErrorView(message: message, context: context)
    case .permission(let kind):
        PermissionView(kind: kind, context: context)
    }
}

// MARK: collapsed

/// The five-cell lamp under the notch. It is the only thing the idle state
/// paints, and it is the shared `IdleLampView` so its motion is one implementation.
private struct CollapsedView: View {
    @Environment(\.islandReduceMotion) private var reduce

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            IdleLampView(reduceMotion: reduce)
                .padding(.bottom, IslandTokens.Space.xs - IslandTokens.Size.hairline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Superflow")
    }
}

/// The six-second "was that a mistake?" card. The microphone is already closed,
/// so Undo keeps the words by copying them. The accent button is the only blue
/// element and stays inside the content gutter however long the transcript is.
private struct UndoView: View {
    let text: String
    let context: FlowContext

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cancelled.").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                           tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            }
            .frame(height: IslandTokens.Size.band)

            HStack(spacing: IslandTokens.Space.md) {
                Text(text.replacingOccurrences(of: "\n", with: " "))
                    .appType(IslandTokens.TypeRole.reading)
                    .foregroundStyle(IslandTokens.Color.ink)
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .modifier(EdgeFade(length: IslandTokens.Size.cardPad))
                AppButton("Undo", glyph: nil, kind: .primary,
                          height: IslandTokens.Size.control,
                          minimumWidth: IslandTokens.Size.copyWidth) {
                    context.actions.copyTranscript(IslandTranscript(text: text, bundleID: nil,
                                                                     appName: nil, date: .now, words: 0))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.top, IslandTokens.Space.md)
            .padding(.horizontal, IslandTokens.Size.cardPad)
            .frame(height: IslandTokens.Size.row + IslandTokens.Space.md)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: thinking

/// Three stepping cells, the one looping wait mark. Reduce Motion shows the
/// whole mark instead of stepping it.
private struct ThinkingView: View {
    let query: String
    @Environment(\.islandReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            Text("Thinking").appType(IslandTokens.TypeRole.label)
                .foregroundStyle(IslandTokens.Color.ink)
            if !query.isEmpty {
                Text(query).appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(IslandTokens.Color.ink2)
                    .lineLimit(2)
            }
            TimelineView(.animation(paused: reduce)) { timeline in
                let phase = reduce ? 1 : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1) * 3
                HStack(spacing: IslandTokens.Space.sm) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(IslandTokens.Color.wave)
                            .opacity(reduce ? 1 : (Double(i) <= phase ? 1 : 0.25))
                            .frame(width: IslandTokens.Space.sm, height: IslandTokens.Size.hairline * 2)
                    }
                }
            }
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: error

private struct ErrorView: View {
    let message: String
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack(spacing: IslandTokens.Space.sm) {
                IconView(.alert, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.danger)
                Text("Something went wrong").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                dismiss
            }
            Text(message).appType(IslandTokens.TypeRole.body)
                .foregroundStyle(IslandTokens.Color.ink2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            HStack(spacing: IslandTokens.Space.sm) {
                AppButton("Retry", glyph: nil, kind: .secondary, height: IslandTokens.Size.control) {
                    context.actions.retry()
                }
                AppButton("Dismiss", glyph: nil, kind: .quiet, height: IslandTokens.Size.control) {
                    context.actions.dismiss()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dismiss: some View {
        IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                   tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
            .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
    }
}

// MARK: permission

private struct PermissionView: View {
    let kind: IslandPermission
    let context: FlowContext

    private var title: String {
        switch kind {
        case .microphone: "Microphone needed"
        case .screenRecording: "Screen Recording needed"
        case .inputMonitoring: "Input Monitoring needed"
        }
    }

    private var glyph: Icon {
        switch kind {
        case .microphone: .mic
        case .screenRecording: .eyeSlash
        case .inputMonitoring: .keyboard
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack(spacing: IslandTokens.Space.sm) {
                IconView(glyph, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.ink)
                Text(title).appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                           tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            }
            Text("Superflow needs this permission to answer here. Nothing else changes.")
                .appType(IslandTokens.TypeRole.body)
                .foregroundStyle(IslandTokens.Color.ink2)
            Spacer(minLength: 0)
            HStack {
                AppButton("Open Settings", glyph: nil, kind: .primary,
                          height: IslandTokens.Size.control, action: context.actions.openPermissionSettings)
                Spacer(minLength: 0)
            }
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
