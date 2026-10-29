import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowUIComponents
import SwiftUI

struct MeetingDetail: View {
    @ObservedObject var model: PastMeetingsModel
    let document: MeetingDocument
    let proxy: ScrollViewProxy
    let collapse: () -> Void
    @Environment(DialogHost.self) private var dialogs
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hoverTime: TimeInterval?
    @State private var flash: Int?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            header
            VStack(alignment: .leading, spacing: Space.xs) {
                MeetingStrip(document: document, hover: $hoverTime) { time in jump(time) }
                readout
            }
            ForEach(document.notices, id: \.self) { NoticeBanner($0, tone: .orange) }
            turns
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { flashTask?.cancel() }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.sm) { heading; Spacer(); actions }
            VStack(alignment: .leading, spacing: Space.sm) { heading; actions }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            RowButton("Collapse meeting", radius: 0, action: collapse) {
                Text(document.title).font(Typography.sectionTitle).foregroundStyle(Tok.text)
            }
            Text("\(Humanize.when(document.startedAt)) · \(Humanize.duration(Double(document.durationMs) / 1000)) · \(Humanize.words(document.turns.filter { !$0.isGap }.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }))")
                .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
        }
    }

    private var actions: some View {
        HStack(spacing: Space.xs) {
            CopyMarkdownButton(enabled: document.turns.contains {
                !$0.isGap && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) { await model.copyMarkdown(document) }
            NativeActionMenu(items: menu)
        }
    }

    private var menu: [MenuItem] {
        [MenuItem("Rename", glyph: .rename) {
            dialogs.present {
                MeetingRenameDialog(initial: document.title) { title in
                    Task { await model.rename(document.sessionID, to: title) }
                }
            }
        },
        MenuItem("Export Markdown", glyph: .exportOut) { model.export(document, json: false) },
        MenuItem("Export JSON", glyph: .exportOut) { model.export(document, json: true) },
        MenuItem("Delete", glyph: .delete, role: .destructive, gapBefore: true) { model.delete(document) }]
    }

    private var readout: some View {
        HStack {
            Text(hoverTime.map { Segment.timeLabel(Int($0 * 1000)) } ?? "0:00")
            Spacer(minLength: 0)
            Text(Segment.timeLabel(document.durationMs))
        }
        .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2).frame(height: 16)
    }

    private var turns: some View {
        LazyVStack(alignment: .leading, spacing: Space.md) {
            ForEach(document.turns, id: \.id) { turn in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.xs) {
                        Text(turn.speakerName).appType(.label).foregroundStyle(Tok.text)
                        Text(turn.timestampLabel).appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                    }
                    Text(turn.text).appType(.reading).foregroundStyle(turn.isGap ? Tok.text2 : Tok.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(flash == turn.id ? Tok.accentSoft : .clear, in: .rect(cornerRadius: Radius.nested))
                .id(turn.id)
            }
        }
        .animation(reduce ? nil : .easeOut(duration: 0.3), value: flash)
    }

    private func jump(_ time: TimeInterval) {
        guard let turn = document.turns.last(where: { Double($0.startMs) / 1000 <= time }) ?? document.turns.first else { return }
        withAnimation(reduce ? nil : .easeOut(duration: 0.4)) { proxy.scrollTo(turn.id, anchor: .top) }
        flash = turn.id
        flashTask?.cancel()
        flashTask = Task {
            do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
            flash = nil
        }
    }
}

private struct MeetingRenameDialog: View {
    let initial: String
    let onDone: (String) -> Void
    @State private var text = ""
    var body: some View {
        DialogFrame(title: "Rename meeting", confirmTitle: "Save", canConfirm: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onConfirm: { onDone(text) }) {
            AppTextField(text: $text, prompt: initial, autofocus: true)
        }
        .onAppear { text = initial }
    }
}
