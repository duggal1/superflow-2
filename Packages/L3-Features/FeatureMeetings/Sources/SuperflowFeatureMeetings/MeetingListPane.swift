import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

struct MeetingListPane: View {
    @ObservedObject var model: PastMeetingsModel
    @Binding var tab: MeetingsTab
    @State private var searchFocus = false
    @State private var showEmpty = false

    var body: some View {
        let empty = model.groups.flatMap(\.sessions).filter { $0.wordCount == 0 }
        VStack(alignment: .leading, spacing: 16) {
            SearchField(text: $model.query, prompt: "Search meetings", isFocused: $searchFocus)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.groups) { group in
                        let sessions = group.sessions.filter { $0.wordCount > 0 }
                        if !sessions.isEmpty {
                            Section {
                                ForEach(sessions) { session in row(session) }
                            } header: {
                                Text(Humanize.day(group.day)).appType(.caption).foregroundStyle(Tok.text2)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading).background(Tok.bg)
                            }
                        }
                    }
                    if !empty.isEmpty {
                        AppButton("No speech (\(empty.count))", kind: .quiet) { showEmpty.toggle() }
                            .accessibilityValue(showEmpty ? "Expanded" : "Collapsed")
                        if showEmpty { ForEach(empty) { session in row(session) } }
                    }
                }
            }
            .scrollEdgeSoft()
        }
        .padding(.leading, 20).padding(.trailing, 16)
        .searchShortcut($searchFocus)
        .task(id: model.query) { await model.reload() }
        .overlay(alignment: .top) { if let error = model.error { NoticeBanner(error, tone: .rose) } }
    }

    private func row(_ session: SessionRecord) -> some View {
        RowButton(session.wordCount == 0 ? "No speech found" : session.displayTitle,
                  height: session.wordCount == 0 ? 56 : 72,
                  selected: tab == .past && model.selectedID == session.id) {
            tab = .past
            Task { await model.select(session.id) }
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.wordCount == 0 ? "No speech found." : session.displayTitle)
                        .appType(.label).foregroundStyle(session.wordCount == 0 ? Tok.text2 : Tok.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Humanize.duration(Double(session.durationMs) / 1000))
                        .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                }
                Text(Humanize.when(session.startedAt)).appType(.caption).foregroundStyle(Tok.text2)
                if session.wordCount > 0 {
                    MeetingBarcode(turns: model.barcodes[session.id] ?? [], speakers: [],
                                   durationMs: session.durationMs, active: model.selectedID == session.id)
                        .frame(maxWidth: 287, alignment: .leading).frame(height: 6)
                }
            }
            .padding(.horizontal, 12)
        }
        .task { await model.loadBarcode(for: session.id) }
    }
}

struct MeetingDetailPane: View {
    @ObservedObject var model: PastMeetingsModel

    var body: some View {
        Group {
            if let document = model.selectedDocument {
                ScrollViewReader { proxy in
                    ScrollView {
                        MeetingDetail(model: model, document: document, proxy: proxy, collapse: nil)
                            .padding(.horizontal, Layout.pad).padding(.bottom, 48)
                    }
                }
            } else if let error = model.documentError {
                Text(error).appType(.body).foregroundStyle(Tok.text2)
            } else if model.isLoadingDocument {
                ProgressView()
            } else {
                EmptyState("No meetings yet.", message: "Hold right ⌘ or double-tap it to record.", density: .pane)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
