import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

public struct RecentTranscripts: View {
    @ObservedObject private var model: RecentDictationViewModel
    private let openHistory: () -> Void

    public init(model: RecentDictationViewModel, openHistory: @escaping () -> Void) {
        self.model = model
        self.openHistory = openHistory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                SectionHeader("Recent dictation")
                Spacer(minLength: Space.md)
                AppButton("Open History", glyph: nil, kind: .quiet, height: 24, action: openHistory)
            }
            Card(padding: Space.xs) {
                VStack(spacing: 2) {
                    if model.entries.isEmpty { ExampleRow() }
                    else { ForEach(model.entries) { TranscriptRow(entry: $0, model: model) } }
                }
            }
            if let error = model.error { Text(error).appType(.caption).foregroundStyle(Tok.text2) }
        }
        .toast(model.toast)
        .onDisappear { model.stopPlayback() }
    }
}

private struct TranscriptRow: View {
    enum Variant: Hashable { case cleaned, raw }
    let entry: RecentDictationEntry
    @ObservedObject var model: RecentDictationViewModel
    @State private var hover = false
    @State private var mode: Variant = .cleaned
    @State private var menuOpen = false
    @FocusState private var focused: Bool

    private var playing: Bool { model.playingID == entry.id }
    private var expanded: Bool { model.expandedID == entry.id && !playing }
    private var revealed: Bool { hover || focused || menuOpen || expanded }
    private var shown: String { mode == .raw && !entry.raw.isEmpty ? entry.raw : entry.cleaned }
    private var failed: Bool {
        entry.record.status == .failed || entry.record.status == .cancelled || entry.failure != nil
    }

    private var title: String {
        if entry.retrying { return "Transcribing" }
        if let failure = entry.failure { return failure }
        if entry.record.status == .cancelled { return "Cancelled. Audio kept." }
        if entry.record.status == .failed { return "Transcription failed." }
        return entry.cleaned.isEmpty ? "No speech found." : entry.cleaned.replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if playing {
                PlayerBar(entry: entry, model: model)
                    .transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    RowButton(title, height: 56, hoverFill: .clear,
                              action: { model.toggle(entry.id) }) { label }
                        .focused($focused)
                        .focusEffectDisabled()
                    actions
                }
                .frame(height: 56)
                .transition(.opacity)
            }
            if expanded { detail.transition(.opacity) }
        }
        .padding(.horizontal, Space.sm)
        .background(playing ? Tok.well : hover ? Tok.control : .clear,
                    in: .rect(cornerRadius: Radius.nested, style: .continuous))
        .overlay(alignment: .leading) {
            if expanded || playing { Rectangle().fill(Ramp.blue[4]).frame(width: 2, height: 16) }
        }
        .onHover { inside in
            hover = inside
            if inside, let url = entry.audio {
                RowClipLoader.preload(url)
                model.audio.prewarm()                                   // zero-lag Play
            }
        }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .animation(.smooth(duration: 0.30), value: playing)
        .animation(.smooth(duration: 0.30), value: expanded)
    }

    private var label: some View {
        HStack(spacing: Space.sm) {
            if let bundle = entry.record.frontmostBundleID { AppIcon(bundleID: bundle, size: 20) }
            else { Icon(.mic, size: 14, tint: Tok.text2).frame(width: 20, height: 20) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appType(.label)
                    .foregroundStyle(failed ? Tok.text2 : Tok.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .modifier(TextFade(length: 32))
                HStack(spacing: Space.sm) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(Humanize.when(entry.record.startedAt, now: context.date))
                    }
                    Text(Humanize.duration(Double(entry.record.durationMs) / 1000))
                    if !failed { Text(Humanize.words(entry.record.wordCount)).monospacedDigit() }
                }
                .appType(.caption)
                .foregroundStyle(Tok.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }

    @ViewBuilder private var actions: some View {
        if entry.retrying {
            Color.clear.frame(width: 32, height: 32)
        } else if failed {
            HStack(spacing: Space.sm) {
                Badge(entry.record.status == .cancelled ? "Cancelled" : "Failed")
                AppButton("Retry transcript", glyph: nil, kind: .secondary, height: 24) { model.retry(entry) }
                    .disabled(entry.audio == nil || !model.canRetry)
                ActionMenu(actions: menu, isOpen: $menuOpen).focused($focused)
            }
            .padding(.trailing, -8)
        } else {
            HStack(spacing: 4) {
                if entry.audio != nil {
                    BarIconButton(glyph: .play, label: "Play audio") { model.play(entry) }
                        .focused($focused)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
                BarIconButton(glyph: .copy, label: "Copy transcript") { model.copy(shown) }
                    .focused($focused)
                ActionMenu(actions: menu, isOpen: $menuOpen).focused($focused)
            }
            .padding(.trailing, -8)                                     // glyph edge, not the 32 pt target
            .opacity(revealed ? 1 : 0)
            .allowsHitTesting(revealed)
            .animation(revealed ? Motion.hoverIn : Motion.hoverOut, value: revealed)
        }
    }

    private var menu: [ActionMenu.Action] {
        var actions: [ActionMenu.Action] = []
        if entry.audio != nil, model.canRetry {
            actions.append(.init("Retry transcript", run: { model.retry(entry) }))
        }
        actions.append(.init("Delete transcript", run: { model.delete(entry) }))
        if entry.audio != nil { actions.append(.init("Extract audio", run: { model.extractAudio(entry) })) }
        return actions
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if !entry.raw.isEmpty {
                Segmented(selection: $mode,
                          items: [.init("Cleaned", value: .cleaned), .init("Raw", value: .raw)],
                          onCard: true)
            }
            Text(shown).appType(.reading).foregroundStyle(Tok.text)
                .textSelection(.enabled)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .padding(.leading, 32)
        .padding(.bottom, Space.md)
    }
}

struct ExampleRow: View {
    var body: some View {
        HStack(spacing: Space.sm) {
            Icon(.mic, size: 14, tint: Tok.text2).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("The budget is $12,000, and we meet on Tuesday at 3 PM.")
                    .appType(.label)
                    .foregroundStyle(Tok.text)
                Text("Hold fn and speak.").appType(.caption).foregroundStyle(Tok.text2)
            }
            Spacer(minLength: Space.md)
            Badge("Example")
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 56)
    }
}
