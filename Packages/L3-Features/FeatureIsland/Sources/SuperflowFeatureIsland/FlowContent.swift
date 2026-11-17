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

/// The pixel band that runs along the bottom of a card. Quiet at rest, a live
/// signal while the card is doing work. One more place the readout is made of
/// cells rather than a generic progress bar.
private struct PixelCardFooter: View {
    var active: Bool = false

    var body: some View {
        VStack(spacing: IslandTokens.Space.xs) {
            PixelRule(tone: Ramp.blue[1])
            PixelBand(active: active, cells: 24)
        }
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
            PixelHeading(glyph: PixelGlyphs.warning, title: "Cancelled.", tone: Ramp.blue[3])
                .padding(.horizontal, IslandTokens.Size.cardPad)
                .frame(height: IslandTokens.Size.band)
            PixelFlowRail(active: 2)
                .padding(.horizontal, IslandTokens.Size.cardPad)

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
            PixelCardFooter(active: false)
                .padding(.horizontal, IslandTokens.Size.cardPad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed()
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
            PixelHeading(glyph: PixelGlyphs.thinking, title: "Thinking", tone: Ramp.blue[3])
            PixelFlowRail(active: 3)
            if !query.isEmpty {
                Text(query).appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(IslandTokens.Color.ink2)
                    .lineLimit(2)
            }
            // The one live mark: a pixel sweep travelling the data band instead
            // of three generic stepping rectangles.
            HStack(spacing: IslandTokens.Space.md) {
                PixelSweep()
                PixelBand(active: !reduce, cells: 18)
            }
            if reduce {
                Text("Working").appType(IslandTokens.TypeRole.caption)
                    .foregroundStyle(IslandTokens.Color.ink2)
            }
            Spacer(minLength: 0)
            PixelRule(tone: Ramp.blue[1])
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed(tone: Ramp.blue[2], hot: Ramp.blue[3])
    }
}

// MARK: error

private struct ErrorView: View {
    let message: String
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack(spacing: IslandTokens.Space.sm) {
                PixelBitmap(rows: PixelGlyphs.warning, cell: PixelInstrument.cell,
                            gap: PixelInstrument.gap, tone: IslandTokens.Color.danger)
                Text("Something went wrong").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                dismiss
            }
            .frame(height: IslandTokens.Size.glyph)
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
            PixelRule(tone: Ramp.blue[1])
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed(tone: Ramp.blue[2], hot: IslandTokens.Color.danger)
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

    private var glyph: [String] {
        switch kind {
        case .microphone: PixelGlyphs.listening
        case .screenRecording: PixelGlyphs.answer
        case .inputMonitoring: PixelGlyphs.settings
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack(spacing: IslandTokens.Space.sm) {
                PixelBitmap(rows: glyph, cell: PixelInstrument.cell,
                            gap: PixelInstrument.gap, tone: IslandTokens.Color.wavePeak)
                Text(title).appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                           tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            }
            .frame(height: IslandTokens.Size.glyph)
            Text("Superflow needs this permission to answer here. Nothing else changes.")
                .appType(IslandTokens.TypeRole.body)
                .foregroundStyle(IslandTokens.Color.ink2)
            Spacer(minLength: 0)
            HStack {
                AppButton("Open Settings", glyph: nil, kind: .primary,
                          height: IslandTokens.Size.control, action: context.actions.openPermissionSettings)
                Spacer(minLength: 0)
            }
            PixelRule(tone: Ramp.blue[1])
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed(tone: Ramp.blue[2], hot: IslandTokens.Color.danger)
    }
}
