import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

public struct IslandActions: Sendable {
    public var start: @Sendable () -> Void
    public var stop: @Sendable () -> Void
    public var cancel: @Sendable () -> Void
    public var openApp: @Sendable () -> Void
    public var openSettings: @Sendable () -> Void
    public var quit: @Sendable () -> Void

    public init(start: @escaping @Sendable () -> Void = {},
                stop: @escaping @Sendable () -> Void = {},
                cancel: @escaping @Sendable () -> Void = {},
                openApp: @escaping @Sendable () -> Void = {},
                openSettings: @escaping @Sendable () -> Void = {},
                quit: @escaping @Sendable () -> Void = {}) {
        self.start = start
        self.stop = stop
        self.cancel = cancel
        self.openApp = openApp
        self.openSettings = openSettings
        self.quit = quit
    }
}

public struct IslandView: View {
    @ObservedObject private var model: IslandViewModel
    private let actions: IslandActions
    private let onMove: @MainActor @Sendable (CGSize) -> Void
    @State private var lastDragTranslation = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: IslandViewModel, actions: IslandActions = IslandActions(),
                onMove: @escaping @MainActor @Sendable (CGSize) -> Void = { _ in }) {
        self.model = model
        self.actions = actions
        self.onMove = onMove
    }

    public var body: some View {
        GlassSurface(radius: model.isExpanded ? Radius.islandExpanded : Radius.islandCompact,
                     style: .interactive) {
            Group {
                if model.isIdle {
                    if model.showIdlePill { idlePill }
                } else if model.isExpanded {
                    expanded
                } else {
                    compact
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
        }
        .frame(width: model.isExpanded ? IslandMetrics.expandedWidth : IslandMetrics.compactWidth)
        .fixedSize(horizontal: true, vertical: true)
        .animation(reduceMotion ? nil : Motion.settle, value: model.isExpanded)
        .simultaneousGesture(DragGesture(minimumDistance: IslandDragPolicy.threshold)
            .onChanged { value in
                guard IslandDragPolicy.isDrag(value.translation) else { return }
                let delta = CGSize(width: value.translation.width - lastDragTranslation.width,
                                   height: value.translation.height - lastDragTranslation.height)
                lastDragTranslation = value.translation
                onMove(delta)
            }
            .onEnded { _ in lastDragTranslation = .zero }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Superflow \(model.modeLabel)")
    }

    private var idlePill: some View {
        HStack(spacing: Space.sm) {
            Icon(.waveform, size: 14, tint: Tok.accent)
            Text("Superflow")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tok.text)
            Spacer(minLength: Space.xs)
            Text("Hold Fn")
                .font(Typography.secondary)
                .foregroundStyle(Tok.text2)
            IconButton(.mic, label: "Start dictation", size: 14, tint: Tok.accent) {
                actions.start()
            }
        }
        .frame(height: IslandMetrics.compactContentHeight)
    }

    private var compact: some View {
        HStack(spacing: Space.sm) {
            RowButton("Expand \(model.modeLabel)", radius: Radius.field) {
                model.toggleExpanded()
            } content: {
                HStack(spacing: Space.sm) {
                    stateIndicator
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.modeLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Tok.text)
                        if model.phase.isActive {
                            Text(model.elapsedLabel)
                                .font(.system(size: 10, weight: .regular).monospacedDigit())
                                .foregroundStyle(Tok.text2)
                        }
                    }
                }
            }
            Spacer(minLength: Space.xs)
            controls
        }
        .frame(height: IslandMetrics.compactContentHeight)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                stateIndicator
                Text(model.modeLabel)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Tok.text)
                Text(model.elapsedLabel)
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(Tok.text2)
                if model.wordCount > 0 {
                    Text("\(model.wordCount) words")
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                }
                Spacer(minLength: Space.xs)
                controls
                IconButton(.chevronDown, label: "Collapse", size: 14, tint: Tok.text2) {
                    model.toggleExpanded()
                }
                .rotationEffect(.degrees(180))
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                if !model.partial.isEmpty {
                    partialLine(label: "You", text: model.partial)
                }
                if !model.systemPartial.isEmpty {
                    partialLine(label: "Remote", text: model.systemPartial)
                }
                if model.partial.isEmpty, model.systemPartial.isEmpty {
                    Text(emptyPartialText)
                        .font(Typography.body)
                        .foregroundStyle(Tok.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44, alignment: .topLeading)

            if let notice = model.notice {
                NoticeBanner(notice, tone: .orange)
            }
        }
    }

    private func partialLine(label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Tok.text2)
                .frame(width: 42, alignment: .leading)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Tok.text)
                .lineLimit(2)
                .truncationMode(.head)
        }
    }

    private var emptyPartialText: String {
        switch model.phase {
        case .warming: "Loading the speech model…"
        case .degraded: "Session continues with a limited pipeline."
        case .failed: "The session stopped. Open the app for details."
        default: "Listening…"
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch model.phase {
        case .warming:
            ProgressBar(value: max(0.08, model.progress), height: 3)
                .frame(width: 46)
        case .listening:
            WaveformView(levels: model.levels, tint: Tok.accent, barWidth: 2, spacing: 2)
                .frame(width: 46, height: 16)
        case .finalizing:
            ProgressBar(value: max(0.08, model.progress), height: 3)
                .frame(width: 46)
        case .complete:
            Icon(.checkmark, size: 13, tint: DotTone.green.color)
                .frame(width: 46)
        case .degraded:
            Icon(.alert, size: 13, tint: DotTone.orange.color)
                .frame(width: 46)
        case .failed:
            Icon(.alert, size: 13, tint: DotTone.rose.color)
                .frame(width: 46)
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .listening, .degraded:
            IconButton(.stop, label: "Stop", size: 14, tint: Tok.accent) {
                actions.stop()
            }
            IconButton(.close, label: "Cancel", size: 14, tint: Tok.text2) {
                actions.cancel()
            }
        case .warming:
            IconButton(.close, label: "Cancel", size: 14, tint: Tok.text2) {
                actions.cancel()
            }
        default:
            EmptyView()
        }
    }
}
