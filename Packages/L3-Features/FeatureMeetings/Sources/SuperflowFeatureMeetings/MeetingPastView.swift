import SuperflowDesignSystem
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowUIComponents
import SwiftUI

struct MeetingPastView: View {
    @ObservedObject var model: MeetingsViewModel
    @State private var renamingID: String?

    var body: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            list
            detail
        }
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if model.isEmptyPast {
                EmptyState("No meetings yet.",
                           message: "Finished meetings land here with speakers and exports.",
                           density: .pane)
                    .frame(maxHeight: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.pastSessions) { session in
                            row(session)
                        }
                    }
                }
                .scrollEdgeSoft()
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
    }

    private func row(_ session: SessionRecord) -> some View {
        RowButton(session.displayTitle, height: 64, selected: session.id == model.selectedID) {
            Task { await model.select(session.id) }
        } content: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(alignment: .top, spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.displayTitle)
                            .appType(.body)
                            .foregroundStyle(Tok.text)
                            .lineLimit(1)
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .appType(.caption)
                            .foregroundStyle(Tok.text2)
                    }
                    Spacer(minLength: Space.sm)
                    Text(session.durationLabel)
                        .appType(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                }
                SpeakerBarcode(turns: model.barcodes[session.id] ?? [],
                               durationMs: session.durationMs)
            }
            .padding(.horizontal, Space.xs)
        }
        .task { await model.loadBarcode(for: session.id) }
    }

    @ViewBuilder
    private var detail: some View {
        if let document = model.selectedDocument {
            VStack(alignment: .leading, spacing: Space.md) {
                header(document)
                if !document.notices.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(document.notices, id: \.self) { notice in
                            NoticeBanner(notice, tone: .orange)
                        }
                    }
                }
                transcript(document)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: Space.sm) {
                PixelStop(cells: 11, cell: 3)
                Text("Select a meeting.")
                    .appType(.title)
                    .foregroundStyle(Tok.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ document: MeetingDocument) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(document.title)
                .appType(.title)
                .foregroundStyle(Tok.text)
            HStack(spacing: Space.sm) {
                Text(document.durationLabel)
                    .monospacedDigit()
                Text(document.participantLabel)
                Spacer(minLength: Space.md)
            }
            .appType(.caption)
            .foregroundStyle(Tok.text2)
            SpeakerBarcode(turns: document.turns, durationMs: document.durationMs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transcript(_ document: MeetingDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(document.turns) { turn in
                    turnRow(turn)
                }
            }
            .padding(.bottom, Space.lg)
        }
        .scrollEdgeSoft()
    }

    private func turnRow(_ turn: MeetingTurn) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                speakerLabel(turn)
                Text(turn.timestampLabel)
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
            }
            .frame(width: 120, alignment: .leading)

            Text(turn.text)
                .appType(.reading)
                .foregroundStyle(turn.isGap ? Tok.text2 : Tok.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Space.proseMaxWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func speakerLabel(_ turn: MeetingTurn) -> some View {
        if turn.isGap {
            Text("System audio")
                .appType(.label)
                .foregroundStyle(Tok.text2)
        } else if renamingID == turn.speakerID {
            AppField("Speaker name", prompt: turn.speakerName, text: renameBinding(turn),
                     height: ControlHeight.small, onCard: false,
                     onSubmit: {
                         let name = typedName
                         renamingID = nil
                         typedName = ""
                         Task { await model.renameSpeaker(id: turn.speakerID, label: name) }
                     })
        } else {
            AppButton(turn.speakerName, kind: .quiet, height: ControlHeight.small) {
                renamingID = turn.speakerID
            }
            .help("Rename this speaker")
        }
    }

    @State private var typedName = ""

    private func renameBinding(_ turn: MeetingTurn) -> Binding<String> {
        Binding(
            get: { typedName.isEmpty ? turn.speakerName : typedName },
            set: { typedName = $0 }
        )
    }

}

/// 96 cells, one per time slice, coloured by who spoke. The shape of a meeting
/// at a glance, in the same pixel language as the rest of the product.
struct SpeakerBarcode: View {
    let turns: [MeetingTurn]
    let durationMs: Int
    private let cells = 96

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<cells, id: \.self) { index in
                Rectangle()
                    .fill(color(at: index))
                    .frame(width: 3, height: 12)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        guard durationMs > 0 else { return Tok.controlHover }
        let time = Double(index) * Double(durationMs) / Double(cells)
        guard let turn = turns.first(where: {
            Double($0.startMs) <= time && time < Double($0.endMs) && !$0.isGap
        }) else { return Tok.controlHover }
        if turn.speakerID == "self" { return Tok.accent }
        let remotes = turns.filter { $0.speakerID != "self" && !$0.isGap }
            .reduce(into: [String]()) { order, turn in
                if !order.contains(turn.speakerID) { order.append(turn.speakerID) }
            }
        let position = remotes.firstIndex(of: turn.speakerID) ?? 0
        let opacities: [Double] = [1, 0.6, 0.35]
        return Tok.text2.opacity(opacities[min(position, opacities.count - 1)])
    }
}
