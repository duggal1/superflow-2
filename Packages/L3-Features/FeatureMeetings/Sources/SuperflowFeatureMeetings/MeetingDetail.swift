import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowUIComponents
import SwiftUI

struct MeetingDetail: View {
    @ObservedObject var model: PastMeetingsModel
    let document: MeetingDocument
    @Environment(DialogHost.self) private var dialogs
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hoverTime: TimeInterval?
    @State private var flash: Int?
    @State private var copied = false
    @State private var flashTask: Task<Void, Never>?
    @State private var copyTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    VStack(alignment: .leading, spacing: 8) {
                        MeetingStrip(document: document, hover: $hoverTime) { time in jump(time, proxy: proxy) }
                        readout
                    }
                    ForEach(document.notices, id: \.self) { NoticeBanner($0, tone: .orange) }
                    turns
                }
                .padding(.horizontal, Layout.pad).padding(.bottom, 48)
            }
        }
        .onDisappear { copyTask?.cancel(); flashTask?.cancel() }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            AppButton(copied ? "Copied" : "Copy as Markdown", glyph: copied ? .checkmark : .copy,
                      kind: .primary, height: 28) {
                copyTask?.cancel()
                copyTask = Task {
                    copied = await model.copyMarkdown(document)
                    do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                    copied = false
                }
            }
            ActionMenu(items: menu).padding(.trailing, -8)
        }
        .fixedSize()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(document.title).appType(.title).foregroundStyle(Tok.text).lineLimit(1)
                        .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                    actions
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(document.title).appType(.title).foregroundStyle(Tok.text)
                    actions
                }
            }
            HStack(spacing: 12) {
                Text(Humanize.when(document.startedAt))
                Text(Humanize.duration(Double(document.durationMs) / 1000))
                Text(Humanize.words(document.turns.filter { !$0.isGap }.reduce(0) {
                    $0 + $1.text.split(whereSeparator: \.isWhitespace).count
                })).monospacedDigit()
            }
            .appType(.caption).foregroundStyle(Tok.text2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    ForEach(Array(document.speakers.prefix(5).enumerated()), id: \.element.id) { index, speaker in
                        share(speaker, index: index).fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(document.speakers.prefix(5).enumerated()), id: \.element.id) { index, speaker in
                        share(speaker, index: index)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func share(_ speaker: MeetingSpeaker, index: Int) -> some View {
        let talk = document.turns.filter { !$0.isGap }
        let total = max(1, talk.reduce(0) { $0 + max(0, $1.endMs - $1.startMs) })
        let own = talk.filter { $0.speakerID == speaker.id }.reduce(0) { $0 + max(0, $1.endMs - $1.startMs) }
        return HStack(spacing: 6) {
            Rectangle().fill(meetingTone(speaker, index: index)).frame(width: 4, height: 4)
            Text(speaker.name).appType(.caption).foregroundStyle(Tok.text).lineLimit(1)
            Text("\(Int((Double(own) / Double(total) * 100).rounded()))%")
                .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
        }
    }

    private var menu: [MenuItem] {
        var items = [MenuItem("Rename meeting", glyph: .history) {
            dialogs.present {
                MeetingRenameDialog(title: "Rename meeting", initial: document.title) { title in
                    Task { await model.rename(document.sessionID, to: title) }
                }
            }
        }]
        for speaker in document.speakers where !speaker.isSelf {
            items.append(MenuItem("Rename \(speaker.name)", glyph: .meetings) {
                dialogs.present {
                    MeetingRenameDialog(title: "Rename speaker", initial: speaker.name) { name in
                        Task { await model.renameSpeaker(id: speaker.id, label: name) }
                    }
                }
            })
        }
        items.append(MenuItem("Export Markdown", glyph: .exportOut, gapBefore: true) { model.export(document, json: false) })
        items.append(MenuItem("Export JSON", glyph: .exportOut) { model.export(document, json: true) })
        items.append(MenuItem("Delete meeting", glyph: .delete, role: .destructive, gapBefore: true) { model.delete(document) })
        return items
    }

    private var readout: some View {
        HStack {
            if let time = hoverTime {
                let ms = Int(time * 1000)
                let speaker = document.turns.last { !$0.isGap && $0.startMs <= ms && ms < $0.endMs }?.speakerName ?? "Silence"
                Text("\(speaker), \(Segment.timeLabel(ms))").foregroundStyle(Tok.text)
            } else {
                Text("0:00").foregroundStyle(Tok.text2)
                Spacer(minLength: 0)
                Text(Segment.timeLabel(document.durationMs)).foregroundStyle(Tok.text2)
            }
        }
        .appType(.caption).monospacedDigit().frame(height: 16)
    }

    private var turns: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(document.turns.enumerated()), id: \.element.id) { index, turn in
                let fresh = index == 0 || document.turns[index - 1].speakerID != turn.speakerID
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        if fresh {
                            HStack(spacing: 6) {
                                if let index = document.speakers.firstIndex(where: { $0.id == turn.speakerID }) {
                                    Rectangle().fill(meetingTone(document.speakers[index], index: index)).frame(width: 4, height: 4)
                                }
                                Text(turn.speakerName).appType(.label).foregroundStyle(Tok.text).lineLimit(1)
                            }
                        }
                        Text(turn.timestampLabel).appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                    }
                    .frame(width: 120, alignment: .leading)
                    Text(turn.text).appType(.reading).foregroundStyle(turn.isGap ? Tok.text2 : Tok.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 0, maxWidth: 560, alignment: .leading)
                }
                .padding(.vertical, 8).padding(.horizontal, 8).padding(.top, fresh && index > 0 ? 12 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(flash == turn.id ? Tok.accentSoft : .clear, in: .rect(cornerRadius: Radius.nested))
                .id(turn.id)
            }
        }
        .animation(reduce ? nil : .smooth(duration: 0.30), value: flash)
    }

    private func jump(_ time: TimeInterval, proxy: ScrollViewProxy) {
        guard let turn = document.turns.last(where: { Double($0.startMs) / 1000 <= time }) ?? document.turns.first else { return }
        withAnimation(reduce ? nil : .smooth(duration: 0.40)) { proxy.scrollTo(turn.id, anchor: .top) }
        flash = turn.id
        flashTask?.cancel()
        flashTask = Task {
            do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
            flash = nil
        }
    }
}

private struct MeetingRenameDialog: View {
    let title: String
    let initial: String
    let onDone: (String) -> Void
    @State private var text = ""
    var body: some View {
        DialogFrame(title: title, confirmTitle: "Save", canConfirm: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onConfirm: { onDone(text) }) {
            AppTextField(text: $text, prompt: initial, autofocus: true)
        }
        .onAppear { text = initial }
    }
}
