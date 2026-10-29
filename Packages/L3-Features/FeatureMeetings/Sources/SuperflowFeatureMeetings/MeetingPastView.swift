import SuperflowDesignSystem
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowUIComponents
import SwiftUI

public struct PastMeetingsView: View {
    @ObservedObject private var model: PastMeetingsModel
    @State private var searchFocus = false
    public init(model: PastMeetingsModel) { self.model = model }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                SearchField(text: $model.query, prompt: "Search meetings", isFocused: $searchFocus)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                        ForEach(model.groups) { group in
                            Section {
                                ForEach(group.sessions) { session in row(session) }
                            } header: {
                                Text(Humanize.day(group.day)).appType(.caption).foregroundStyle(Tok.text2)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading).background(Tok.bg)
                            }
                        }
                    }
                }
            }
            .frame(width: 320)
            Group {
                if let document = model.selectedDocument {
                    MeetingDetail(model: model, document: document).id(document.sessionID)
                } else {
                    EmptyState("No meetings yet.", message: "Hold right ⌘ or double-tap it to record.", density: .pane)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .searchShortcut($searchFocus)
        .task(id: model.query) { await model.reload() }
        .overlay(alignment: .top) {
            if let error = model.error { NoticeBanner(error, tone: .rose) }
        }
    }

    private func row(_ session: SessionRecord) -> some View {
        RowButton(session.displayTitle, height: 64, selected: session.id == model.selectedID) {
            Task { await model.select(session.id) }
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.displayTitle).appType(.label).foregroundStyle(Tok.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Humanize.duration(Double(session.durationMs) / 1000)).appType(.caption)
                        .monospacedDigit().foregroundStyle(Tok.text2).fixedSize()
                }
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .appType(.caption).foregroundStyle(Tok.text2)
                let turns = model.barcodes[session.id] ?? []
                let speakers = speakers(for: turns)
                MeetingBarcode(turns: turns, speakers: speakers, durationMs: session.durationMs)
                    .frame(maxWidth: 287).frame(height: 6)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .overlay(alignment: .leading) {
            if session.id == model.selectedID { Rectangle().fill(Ramp.blue[4]).frame(width: 2, height: 16) }
        }
        .task { await model.loadBarcode(for: session.id) }
    }

    private func speakers(for turns: [MeetingTurn]) -> [MeetingSpeaker] {
        var seen = Set<String>()
        return turns.compactMap { turn in
            guard !turn.isGap, seen.insert(turn.speakerID).inserted else { return nil }
            return MeetingSpeaker(id: turn.speakerID, name: turn.speakerName, isSelf: turn.speakerID == "self")
        }
    }
}
